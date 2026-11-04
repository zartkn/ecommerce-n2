FROM node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

# Instala as dependências primeiro para aproveitar o cache de camadas
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY src ./src

EXPOSE 3000
USER node
CMD ["node", "src/server.js"]
