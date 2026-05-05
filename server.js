const http = require('http');
const SERVICE = process.env.SERVICE_NAME || 'api';
const PORT = process.env.PORT || 8080;
const SCHEMA = process.env.DB_SCHEMA || 'public';
const data = {
  auth:     { tokens: [{id:1,user:'alice',role:'admin'}] },
  users:    { profiles: [{id:1,name:'Alice',email:'alice@demo.local'},{id:2,name:'Bob',email:'bob@demo.local'}] },
  orders:   { orders: [{id:'ORD-001',status:'delivered',total:129.99},{id:'ORD-002',status:'processing',total:59.50}] },
  products: { items: [{id:'P001',name:'Keyboard',price:89.99,stock:142},{id:'P002',name:'USB Hub',price:49.99,stock:89}] },
  notify:   { notifications: [{id:1,type:'email',message:'Order shipped!',status:'sent'}] }
};
http.createServer((req,res) => {
  const p = req.url.split('?')[0];
  let body = {service:SERVICE,schema:SCHEMA,ts:new Date().toISOString()};
  if(p==='/health') body={...body,status:'healthy',uptime:process.uptime().toFixed(1)+'s'};
  else if(p==='/public/info') body={...body,version:'1.0.0'};
  else if(p==='/login') body={token:'eyJhbGciOiJIUzI1NiJ9.demo.sig',expires_in:3600};
  else body={...body,data:data[SCHEMA]||{}};
  res.writeHead(200,{'Content-Type':'application/json','X-Service':SERVICE,'Access-Control-Allow-Origin':'*'});
  res.end(JSON.stringify(body,null,2));
  console.log(new Date().toISOString().slice(11,19),req.method,req.url,'200');
}).listen(PORT,()=>console.log('['+SERVICE+'] :'+PORT+' schema='+SCHEMA));
