FROM node:20-alpine

WORKDIR /app

# Instalar dependencias
COPY package*.json ./
RUN npm ci

# Copiar el resto del código
COPY . .

EXPOSE 3000

CMD ["pnpm", "dev"]