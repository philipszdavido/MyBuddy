> how to find me firebase private key

The key is in a service-account file that you download from the Firebase console.

1. Download the service-account file
1. Go to https://console.firebase.google.com and open the same project the app uses. To check which one that is, look at PROJECT_ID in ios/MyBuddy/GoogleService-Info.plist.
2. Click the gear icon next to Project Overview, then Project settings.
3. Open the Service accounts tab.
4. With Firebase Admin SDK selected, click Generate new private key, then Generate key.
5. A .json file downloads. It contains project_id, client_email and private_key.

2. Copy the values into backend/.env

From the repo root, this fills in the three lines without printing the key on screen. Change the path if the file downloaded somewhere else:

cd backend
python3 - ~/Downloads/your-project-firebase-adminsdk-xxxxx.json <<'EOF'
import json, re, sys
sa = json.load(open(sys.argv[1]))
env = open('.env').read()
values = {
    'FIREBASE_PROJECT_ID': sa['project_id'],
    'FIREBASE_CLIENT_EMAIL': sa['client_email'],
    'FIREBASE_PRIVATE_KEY': '"' + sa['private_key'].replace('\n', '\\n') + '"',
}
for k, v in values.items():
    env = re.sub(rf'^{k}=.*$', lambda m: f'{k}={v}', env, flags=re.M)
open('.env', 'w').write(env)
print('updated', ', '.join(values))
EOF

To do it by hand instead, the key goes on a single line, in double quotes, with its line breaks written as \n:

FIREBASE_PROJECT_ID=your-project-id
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project-id.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"

3. Start the API: npm run dev. If a value is missing or wrong, the server stops at startup and tells you which one.

Keep it secret. This key gives admin access to your Firebase project, including users and push notifications.
- backend/.env is already excluded from git, so it won't be committed.
- After the values are in .env, delete the downloaded .json file or move it somewhere safe. Don't put it inside the repo.
- If it ever leaks, go back to Service accounts, open Manage service account permissions, delete that key, and generate a new one.