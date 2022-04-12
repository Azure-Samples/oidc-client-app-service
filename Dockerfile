FROM node:16-alpine3.14 as build

WORKDIR /app
COPY package.json .
COPY package-lock.json .
COPY /src ./src

RUN npm i --omit dev

FROM node:16-alpine3.14 as runtime

ARG SERVICE_PORT=3000
ENV SERVICE_PORT ${SERVICE_PORT}

WORKDIR /app
COPY --from=build /app/node_modules/ ./node_modules/
COPY --from=build /app/src/ ./src/

# Avoid running your workload as root:
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup
USER appuser

EXPOSE ${SERVICE_PORT}

ENTRYPOINT [ "node", "src/app.js" ]
