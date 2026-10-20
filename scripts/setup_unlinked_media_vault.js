/**
 * Setup Dedicated Unlinked & Standalone Media Vault in Google Drive
 * =================================================================
 * Creates a clean organized section in Vyra_Vault for media files that
 * are standalone device captures (not attached to a specific chat/call).
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const { getDriveAccessToken, VAULT_CONFIG } = require('./drive_service');

function createFolder(token, name, parentId) {
  return new Promise((resolve, reject) => {
    const postData = JSON.stringify({
      name: name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId]
    });

    const req = https.request({
      hostname: 'www.googleapis.com',
      path: '/drive/v3/files?supportsAllDrives=true',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    }, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try {
          const json = JSON.parse(d);
          if (json.id) resolve(json.id);
          else reject(new Error(d));
        } catch (e) { reject(e); }
      });
    });
    req.on('error', reject);
    req.write(postData);
    req.end();
  });
}

async function main() {
  console.log('\n============================================================');
  console.log('📁 SETTING UP DEDICATED UNLINKED STANDALONE MEDIA VAULT');
  console.log('============================================================\n');

  const token = await getDriveAccessToken();
  const rootVaultId = VAULT_CONFIG.vaultId;

  console.log('Creating [Unlinked_Standalone_Media] parent folder in Vyra_Vault...');
  const unlinkedRootId = await createFolder(token, 'Unlinked_Standalone_Media', rootVaultId);
  console.log(`✅ Unlinked Root Folder Created (ID: ${unlinkedRootId})`);

  console.log('Creating categorized subfolders...');
  const screenshotsId = await createFolder(token, 'Standalone_Screenshots', unlinkedRootId);
  const videosId = await createFolder(token, 'Standalone_Videos', unlinkedRootId);
  const memosId = await createFolder(token, 'Standalone_Voice_Memos', unlinkedRootId);

  console.log(`✅ Standalone_Screenshots ID: ${screenshotsId}`);
  console.log(`✅ Standalone_Videos ID: ${videosId}`);
  console.log(`✅ Standalone_Voice_Memos ID: ${memosId}`);

  // Update drive_vault_config.json
  const cfgPath = path.join(__dirname, '../drive_vault_config.json');
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  cfg.unlinkedFolders = {
    root: unlinkedRootId,
    screenshots: screenshotsId,
    videos: videosId,
    voiceMemos: memosId
  };
  fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));

  console.log('\n🎉 Dedicated Unlinked Media Vault successfully configured!');
}

main().catch(console.error);
