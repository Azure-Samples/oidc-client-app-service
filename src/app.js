const express = require('express');
const winston = require('winston');
const { auth, requiresAuth } = require('express-openid-connect');
const Mustache = require('mustache');
const fs = require('fs');


const port = process.env.SERVICE_PORT || 3000;
const scope = process.env.OIDC_SCOPE || 'openid profile email User.Read';
const logLevel = process.env.SERVICE_LOG_LEVEL || 'info';
const logger = winston.createLogger({
    level: logLevel,
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json(),
    ),
    transports: [new winston.transports.Console()],
    defaultMeta: { service: 'sample-oidc-client-app' },
});

const app = express();

app.use(express.static('public'));
app.use(
    auth({
        issuerBaseURL: process.env.OIDC_ISSUER,
        baseURL: process.env.SERVICE_URL,
        clientID: process.env.OIDC_CLIENT_ID,
        secret: process.env.OIDC_CLIENT_SECRET,
        idpLogout: true,
        authRequired: false,
        authorizationParams: { scope },
    })
);
const serviceUrl = process.env.SERVICE_URL;
app.get('/', requiresAuth(), (req, res) => {
    const displayName = req.oidc.user.name || 'Unknown display name';
    const preferredUsername = req.oidc.user.preferred_username || req.oidc.user.sub;
    const parsedIdToken = JSON.stringify(req.oidc.user, null, 2);
    fs.readFile(`${__dirname}/public/index.html`, (err, data) => {
        res.send(Mustache.render(data.toString(), { displayName, preferredUsername, parsedIdToken, serviceUrl }));
    });
});

app.get('/health', (req, res) => {
    res.send({ success: true });
});

app.listen(port, () => {
    logger.info(`Server listening on port %s`, port);
});
