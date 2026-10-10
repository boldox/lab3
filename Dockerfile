# -------------------------------------------------------------
# Etapa 1: Construcción
# -------------------------------------------------------------
FROM node:24 AS construccion

WORKDIR /usr/app

# Copia package.json (y package-lock si existiese)
COPY package*.json ./

# Instalamos todas las dependencias necesarias para compilar
RUN npm install

# Copiamos archivos de configuración y código fuente
COPY nest-cli.json tsconfig*.json ./
COPY src ./src

# Compilamos la aplicación TypeScript (genera la carpeta dist/)
RUN npm run build


# -------------------------------------------------------------
# Etapa 2: Dependencias de producción
# -------------------------------------------------------------
FROM node:24 AS dependencias-produccion

WORKDIR /usr/app

COPY package*.json ./

# Instalamos únicamente las dependencias de producción (sin devDependencies)
RUN npm install --omit=dev


# -------------------------------------------------------------
# Etapa 3: Imagen final ligera (runner)
# -------------------------------------------------------------
FROM node:24-alpine AS runner

WORKDIR /usr/app

# Traemos el package.json y lo compilado desde la etapa 'construccion'
COPY --from=construccion /usr/app/package.json ./
COPY --from=construccion /usr/app/dist ./dist

# Traemos las dependencias limpias desde la etapa 'dependencias-produccion'
COPY --from=dependencias-produccion /usr/app/node_modules ./node_modules

EXPOSE 3000

CMD ["node", "dist/main.js"]