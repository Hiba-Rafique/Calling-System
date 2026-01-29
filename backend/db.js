const mysql = require('mysql2/promise');

let pool;

function getPool() {
  if (pool) return pool;

  pool = mysql.createPool({
    host: process.env.MYSQL_HOST,
    port: process.env.MYSQL_PORT ? Number(process.env.MYSQL_PORT) : 3306,
    user: process.env.MYSQL_USER,
    password: process.env.MYSQL_PASSWORD,
    database: process.env.MYSQL_DATABASE,
    waitForConnections: true,
    connectionLimit: process.env.MYSQL_CONNECTION_LIMIT
      ? Number(process.env.MYSQL_CONNECTION_LIMIT)
      : 10,
    queueLimit: 0,
  });

  return pool;
}

module.exports = { getPool };
