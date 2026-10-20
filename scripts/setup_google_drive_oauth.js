/**
 * Google Drive Personal 5 TB Account OAuth Setup Helper
 * =====================================================
 * Reads client_secret*.json automatically, generates the authorization URL,
 * and exchanges the code for a permanent refresh_token.
 */

const http = require('http');
const https = require('https');
const url = require('url');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const CREDENTIALS_FILE = path.join(__dirname, '../google_user_credentials.json');

function findClientSecretFile() {
  const rootDir = path.join(__dirname, '..');
  const files = fs.readdirSync(rootDir);
  for (const f of files) {
    if (f.startsWith('client_secret') && f.endsWith('.json')) {
      return path.join(rootDir, f);
    }
  }
  return null;
}

async function exchangeCodeForTokens(code, clientId, clientSecret, redirectUri) {
  const postData = `code=${encodeURIComponent(code)}&client_id=${encodeURIComponent(clientId)}&client_secret=${encodeURIComponent(clientSecret)}&redirect_uri=${encodeURIComponent(redirectUri)}&grant_type=authorization_code`;

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try {
          const json = JSON.parse(d);
          if (json.refresh_token) {
            resolve(json);
          } else {
            reject(new Error('No refresh token received: ' + d));
          }
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function main() {
  console.log('\n============================================================');
  console.log('🚀 VYRA — GOOGLE DRIVE 5 TB PERSONAL ACCOUNT LINKING');
  console.log('============================================================\n');

  const secretPath = findClientSecretFile();
  if (!secretPath) {
    console.error('❌ Could not find client_secret*.json in workspace.');
    process.exit(1);
  }

  const secretJson = JSON.parse(fs.readFileSync(secretPath, 'utf8'));
  const installed = secretJson.installed || secretJson.web;
  const clientId = installed.client_id;
  const clientSecret = installed.client_secret;

  console.log(`✅ Loaded OAuth credentials: [${clientId.substring(0, 25)}...]`);

  // Local loopback server
  const PORT = 8085;
  const redirectUri = `http://localhost:${PORT}/oauth2callback`;
  const scope = encodeURIComponent('https://www.googleapis.com/auth/drive');
  const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(clientId)}&redirect_uri=${encodeURIComponent(redirectUri)}&response_type=code&scope=${scope}&access_type=offline&prompt=consent`;

  console.log('\n------------------------------------------------------------');
  console.log('👉 STEP 1: OPEN THIS LINK IN CHROME (LOGGED IN AS abhadoria014@gmail.com):');
  console.log('------------------------------------------------------------\n');
  console.log(authUrl);
  console.log('\n------------------------------------------------------------');
  console.log('Waiting for authorization (or you can paste the redirected URL below)...');
  console.log('------------------------------------------------------------\n');

  let server;
  let finished = false;

  const saveAndExit = (tokenJson) => {
    if (finished) return;
    finished = true;
    const creds = {
      client_id: clientId,
      client_secret: clientSecret,
      refresh_token: tokenJson.refresh_token,
      access_token: tokenJson.access_token,
      expiry_date: Date.now() + (tokenJson.expires_in || 3600) * 1000
    };
    fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(creds, null, 2));
    console.log('\n🎉 SUCCESS! Linked your 5 TB Google Drive account.');
    console.log('Saved to: google_user_credentials.json (gitignored).\n');
    if (server) server.close();
    process.exit(0);
  };

  server = http.createServer(async (req, res) => {
    const parsed = url.parse(req.url, true);
    if (parsed.pathname === '/oauth2callback') {
      const code = parsed.query.code;
      if (code) {
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        res.end(`
          <div style="font-family: system-ui; text-align: center; padding: 50px; background: #0f172a; color: white;">
            <h1 style="color: #38bdf8;">🎉 Vyra 5 TB Google Drive Linked!</h1>
            <p style="color: #94a3b8; font-size: 16px;">Authorization successful. You can close this browser tab.</p>
          </div>
        `);
        try {
          const tokenJson = await exchangeCodeForTokens(code, clientId, clientSecret, redirectUri);
          saveAndExit(tokenJson);
        } catch (e) {
          console.error('❌ Token exchange error:', e.message);
        }
      }
    }
  });

  server.listen(PORT);

  // Fallback: also accept pasted code / URL in terminal
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  rl.question('If browser does not auto-redirect, paste the URL or Code here: ', async (ans) => {
    rl.close();
    let code = ans.trim();
    if (code.includes('code=')) {
      const u = new URL(code.startsWith('http') ? code : `http://localhost?${code}`);
      code = u.searchParams.get('code');
    }
    if (code) {
      try {
        const tokenJson = await exchangeCodeForTokens(code, clientId, clientSecret, redirectUri);
        saveAndExit(tokenJson);
      } catch (e) {
        console.error('❌ Token exchange error from input:', e.message);
      }
    }
  });
}

main().catch(console.error);
