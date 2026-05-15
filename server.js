const http = require('http');
const SERVICE = process.env.SERVICE_NAME || 'api';
const PORT = process.env.PORT || 8080;

http.createServer((req,res) => {
  const p = req.url.split('?')[0];
  let body = {service:SERVICE, status:'ok', timestamp: new Date().toISOString()};
  
  if(p==='/health') body={...body, status:'healthy'};
  else if(p==='/login') body={token:'mock-jwt-token-for-testing', expires_in:3600};
  else body={...body, message:'Mock API response', path: p};
  
  res.writeHead(200,{'Content-Type':'application/json'});
  res.end(JSON.stringify(body,null,2));
}).listen(PORT,()=>console.log(`[${SERVICE}] running on :${PORT}`));
