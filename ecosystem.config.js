module.exports = {
  apps : [{
    name: 'eh-api-service',
    script: 'gunicorn',
    args: '-w 4 -b 0.0.0.0:8000 index:app',
    interpreter: 'none',
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    merge_logs: true,
    max_memory_restart: '200M',
    autorestart: true,
  }]
};
