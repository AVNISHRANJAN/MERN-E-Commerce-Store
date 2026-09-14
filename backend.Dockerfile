FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY backend ./backend

ENV NODE_ENV=production
EXPOSE 5000

CMD ["node", "backend/index.js"]