const http = require('http');

const port = process.env.PORT || 80;

const server = http.createServer((request, response) => {
    response.writeHead(200, { "Content-Type": "text/html" });

    console.log(`Request: ${new Date}`);

    const html = `<html>
    <head>
        <title>Blanko app</title>
    </head>
    <body>
    <h2>Blanko app</h2>
    WEBSITE_SITE_NAME:<br />
    <b>${process.env.WEBSITE_SITE_NAME}</b><br /><br />
    REGION_NAME:<br />
    <b>${process.env.REGION_NAME}</b><br /><br />
    COMPUTERNAME:<br /><b>${process.env.COMPUTERNAME}</b>
    </body>
    </html>`;
    response.end(html);
});

server.listen(port);
console.log("App running at port %d", port);
