cd "C:\Users\steve\OneDrive\Documents\GitHub\radio"
git fetch origin
git checkout main
# overwrite the file locally with the correct content, then:
git add lib/main.dart
git commit -m "Restore valid main.dart (seed GPS and start tracking)"
git push origin main
