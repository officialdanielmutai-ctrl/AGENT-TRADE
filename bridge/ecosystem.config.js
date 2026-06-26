module.exports = {
  apps: [
    {
      name: 'leintum-bridge',
      script: 'server.js',
      cwd: './bridge',
      watch: false,
      max_memory_restart: '200M',
      error_file: './logs/bridge-error.log',
      out_file: './logs/bridge-out.log',
      merge_logs: true,
      env: {
        NODE_ENV: 'production',
      },
    },
  ],
};
