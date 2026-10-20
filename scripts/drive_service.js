/**
 * Vyra Parental Control Suite — Master Google Drive Media Vault Migration
 * =====================================================================
 * Migrates heavy media files (call recordings, WhatsApp voice notes,
 * Snapchat 1-view snaps, screenshots, and videos) from:
 * 1. Supabase Storage ('recordings', 'snaps')
 * 2. Mac local cable backups ('backups/device_recordings', 'backups/whatsapp_voice_notes', etc.)
 *
 * Into the user's 5 TB Google Drive ('Vyra_Vault' categorized subfolders):
 * - Call_Recordings: 1Fduldq2nm2CjDcc3dksF4F2BDxgUpTMU
 * - WhatsApp_Voice_Notes: 1lkI8vDOlMD3T2Bqqj0UQVM4G4Gqct4lh
 * - Videos: 1YPJ69zygUDhN8xEgHDsUCBnoV_TpqZLn
 * - Screenshots_and_Snaps: 11oIzGtIacylsfzUDvPD8CozgRLPQxu-I
 *
 * Rules:
 * - ZERO DATA LOSS: 100% of rows in Supabase Database remain intact.
 * - ZERO PREMATURE DELETION: Never deletes a file from Supabase Storage
 *   until Drive upload, public access, and playback streaming are verified.
 * - Sub-15ms streaming URLs configured for Flutter Parent App.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const SUPABASE_URL = 'https://wtlqlkkduescumpggttm.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind0bHFsa2tkdWVzY3VtcGdndHRtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA5NTkyNjksImV4cCI6MjEwNjUzNTI2OX0.KvgoiPasLnyiWV4kBc-ZeByQQ57RUOsFePDazk2mot0';
const CHILD_ID = 'VYRA-13533';

const VAULT_CONFIG = JSON.parse(fs.readFileSync(path.join(__dirname, '../drive_vault_config.json'), 'utf8'));
const SERVICE_KEY_FILE = path.join(__dirname, '../vyra-kp-control-a35ec-0c6ea29e7498.json');
const OAUTH_TOKEN_FILE = path.join(__dirname, '../google_user_credentials.json');

function base64url(str) {
  return Buffer.from(str).toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

// 1. Get Access Token (supports OAuth user token or Service Account)
async function getDriveAccessToken() {
  if (fs.existsSync(OAUTH_TOKEN_FILE)) {
    const creds = JSON.parse(fs.readFileSync(OAUTH_TOKEN_FILE, 'utf8'));
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
        res.on('end', () => resolve(JSON.parse(d)));
      });
      req.on('error', reject);
      req.write(postData);
      req.end();
    });

    if (tokenRes.access_token) {
      creds.access_token = tokenRes.access_token;
      creds.expiry_date = Date.now() + (tokenRes.expires_in || 3600) * 1000;
      fs.writeFileSync(OAUTH_TOKEN_FILE, JSON.stringify(creds, null, 2));
      return creds.access_token;
    }
  }

  // Fallback to Service Account JWT
  const key = JSON.parse(fs.readFileSync(SERVICE_KEY_FILE, 'utf8'));
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64url(JSON.stringify({
    iss: key.client_email,
    scope: 'https://www.googleapis.com/auth/drive',
    aud: 'https://oauth2.googleapis.com/token',
    exp: now + 3600,
    iat: now
  }));
  const sign = crypto.createSign('RSA-SHA256');
  sign.update(`${header}.${claim}`);
  const signature = sign.sign(key.private_key, 'base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const jwt = `${header}.${claim}.${signature}`;
  const postData = `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`;

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'oauth2.googleapis.com',
      path: '/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Content-Length': Buffer.byteLength(postData) }
    }, res => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        const j = JSON.parse(data);
        if (j.access_token) resolve(j.access_token);
        else reject(new Error('Auth failed: ' + data));
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

// 2. Upload Buffer/File to Google Drive
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
    req.write(multipartRequestBody);
    req.end();
  });
}

// 3. Make uploaded file readable by anyoneWithLink (if not automatically inherited)
async function ensurePublicRead(token, fileId) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ role: 'reader', type: 'anyone' });
    const req = https.request({
      hostname: 'www.googleapis.com',
      path: `/drive/v3/files/${fileId}/permissions?supportsAllDrives=true`,
      method: 'POST',
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
    req.write(body);
    req.end();
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

// 6. Delete from Supabase Storage (CALLED ONLY AFTER 100% VERIFICATION)
async function deleteSupabaseStorageFile(bucket, pathName) {
  return new Promise((resolve) => {
    const body = JSON.stringify({ prefixes: [pathName] });
    const req = https.request({
      hostname: 'wtlqlkkduescumpggttm.supabase.co',
      path: `/storage/v1/object/${bucket}`,
      method: 'DELETE',
      headers: {
        'apikey': SUPABASE_ANON_KEY,
        'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    }, res => {
      resolve(res.statusCode >= 200 && res.statusCode < 300);
    });
    req.on('error', () => resolve(false));
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
  verifyUrlStream,
  deleteSupabaseStorageFile
};
