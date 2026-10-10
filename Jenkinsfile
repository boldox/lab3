// ==============================================================================
// Pipeline principal: integracion continua (CI) y entrega/despliegue (CD)
// ==============================================================================
// CI: instala dependencias, ejecuta lint y pruebas, y compila NestJS.
// CD: construye y publica imagenes en Docker Hub; despliega en Kubernetes.
// Las etapas se ejecutan en orden. Un sh que termina con codigo distinto de cero
// falla el paso y normalmente impide continuar con las etapas siguientes.
//
// Requisitos de Jenkins: Declarative Pipeline, Kubernetes plugin para el agente
// y Kubernetes CLI plugin para withKubeConfig. El checkout debe incluir
// agent.yaml, Dockerfile y los archivos de dependencias de la aplicacion.
// regcred-dh es un Secret del namespace del agente, montado en BuildKit;
// kubernetes-config es una credencial de Jenkins para el despliegue.
// Son mecanismos distintos: publicar una imagen no concede permisos en Kubernetes.
//
// Documentacion: https://www.jenkins.io/doc/book/pipeline/syntax/
// Plugins: https://plugins.jenkins.io/kubernetes/
//          https://plugins.jenkins.io/kubernetes-cli/

// Bloque raiz de un pipeline declarativo.
pipeline {
    // Alternativa comentada: agent any usaria cualquier agente disponible.
    // Este ejemplo elige un agente Kubernetes con herramientas especificas.
    // agent any
    // Define donde se ejecutan los pasos, salvo que una etapa lo cambie.
    agent {
        // El plugin Kubernetes crea un Pod temporal para ejecutar el pipeline.
        kubernetes {
            // Los sh sin container(...) se ejecutan en node-tool.
            defaultContainer 'node-tool'
            // Lee la plantilla del Pod desde el archivo versionado del repositorio.
            yamlFile 'agent.yaml'
        }
    }
    // Variables de entorno disponibles para todas las etapas y sus comandos shell.
    environment {
        // Repositorio de destino en Docker Hub, sin etiqueta.
        DH_REPO = 'boldox/lab3'
        // Etiqueta fija requerida por la personalizacion de la pauta.
        DH_TAG = 'diego-bonilla'
        // Namespace de la aplicacion que se actualizara durante el despliegue.
        K8S_NAMESPACE = 'ns-diego-bonilla'
        // Nombre del deployment en Kubernetes.
        K8S_DEPLOYMENT = 'app-diego-bonilla'
    }
    // Lista ordenada de etapas requeridas: install, test, build, push y deploy.
    stages {
        // ==============================================================================
        // Stage 1: install (activacion de pnpm e instalacion de dependencias)
        // ==============================================================================
        stage('install') {
            steps {
                // Corepack habilita los ejecutables del gestor declarado en packageManager
                // de package.json; el proyecto fija pnpm@11.1.2.
                sh 'corepack enable'
                // Muestra la version de Node del agente, no la version de la imagen final de la API.
                sh 'node --version'
                // Permite comprobar en el log que se esta usando el pnpm esperado.
                sh 'pnpm --version'
                // No actualiza pnpm-lock.yaml; falla si no coincide con package.json.
                // Instala tambien dependencias de desarrollo necesarias para Jest y build.
                sh 'pnpm install --frozen-lockfile'
            }
        }

        // ==============================================================================
        // Stage 2: test (ejecucion de pruebas automatizadas)
        // ==============================================================================
        stage('test') {
            steps {
                // Ejecuta scripts.lint de package.json opcionalmente para revision.
                sh 'pnpm lint || true'
                // Ejecuta Jest mediante scripts.test, que habilita los modulos VM para NestJS 12.
                // --runInBand usa un solo proceso para reducir memoria en el agente Node.
                sh 'pnpm test --runInBand'
            }
        }

        // ==============================================================================
        // Stage 3: build (construccion de la imagen con BuildKit)
        // ==============================================================================
        stage('build') {
            steps {
                // Cambia de node-tool a buildkit sin abandonar el Pod ni su workspace.
                container('buildkit') {
                    // buildctl-daemonless.sh inicia BuildKit para esta construccion, sin usar el
                    // daemon Docker del host. Las barras finales continuan el comando en otra linea.
                    // --frontend dockerfile.v0 interpreta las instrucciones del Dockerfile.
                    // --local context=. envia el directorio actual como contexto de construccion.
                    // --local dockerfile=. indica donde encontrar el Dockerfile.
                    // --output type=image exporta una imagen. push=false solo construye sin subir.
                    sh '''
                        buildctl-daemonless.sh build \
                        --frontend dockerfile.v0 \
                        --local context=. \
                        --local dockerfile=. \
                        --output type=image,\\\"name=${DH_REPO}:${DH_TAG}\\\",push=false
                    '''
                }
            }
        }

        // ==============================================================================
        // Stage 4: push (publicacion de la imagen en Docker Hub)
        // ==============================================================================
        stage('push') {
            steps {
                container('buildkit') {
                    // Bloque shell de varias lineas. Las comillas simples triples evitan que Groovy
                    // interpole las variables; ${...} se expande despues en el shell.
                    sh '''
                        # Selecciona la CARPETA que contiene config.json con autenticacion para Docker Hub.
                        export DOCKER_CONFIG=/docker-config/dockerhub
                        # Falla si el archivo no existe o esta vacio, sin imprimir las credenciales.
                        test -s ${DOCKER_CONFIG}/config.json

                        # Publica la imagen en Docker Hub con la etiqueta correspondiente.
                        # push=true publica las etiquetas en el registro.
                        buildctl-daemonless.sh build \
                        --frontend dockerfile.v0 \
                        --local context=. \
                        --local dockerfile=. \
                        --output type=image,\\\"name=${DH_REPO}:${DH_TAG}\\\",push=true
                    '''
                }
            }
        }

        // ==============================================================================
        // Stage 5: deploy (despliegue y verificacion en Kubernetes)
        // ==============================================================================
        stage('deploy') {
            steps {
                // Ejecuta kubectl en la imagen que contiene las herramientas de Kubernetes.
                container('kubectl-tool') {
                    // El plugin crea temporalmente un kubeconfig usando la credencial de Jenkins
                    // kubernetes-config. La identidad debe tener permisos RBAC en el namespace.
                    withKubeConfig([credentialsId: 'kubernetes-config']) {
                        sh '''
                            # Aplica los manifiestos definidos en entrega.yaml
                            kubectl apply -f entrega.yaml
                            # Espera e informa el resultado del rollout. Los probes de readiness ayudan
                            # a determinar cuando los Pods nuevos estan listos para atender trafico.
                            kubectl -n ${K8S_NAMESPACE} rollout status deployment/${K8S_DEPLOYMENT}
                        '''
                    }
                }
            }
        }
    }
}