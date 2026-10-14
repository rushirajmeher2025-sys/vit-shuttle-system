FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm install --production

# Copy the rest of the application
COPY . .

# Expose the WebSocket server port
EXPOSE 8080

# Run the server
CMD ["node", "server.js"]
