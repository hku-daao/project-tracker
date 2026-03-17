const http = require('http');

const PORT = process.env.PORT || 3000;

// CORS headers so Flutter web (any origin) can call this API
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, Accept',
  'Access-Control-Max-Age': '86400',
};

function applyCors(res, statusCode, extraHeaders = {}) {
  res.writeHead(statusCode, { ...corsHeaders, ...extraHeaders });
}

const server = http.createServer((req, res) => {
  // Handle CORS preflight (browser sends OPTIONS before GET when needed)
  if (req.method === 'OPTIONS') {
    applyCors(res, 204);
    res.end();
    return;
  }

  applyCors(res, 200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    ok: true,
    message: 'Project Tracker backend',
    timestamp: new Date().toISOString(),
  }));
});

server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});
