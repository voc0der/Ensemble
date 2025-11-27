# F-Droid Submission Guide

This document contains instructions for submitting Assistant To The Music to F-Droid.

## Prerequisites

✅ MIT License added
✅ All dependencies are open source
✅ No Google Services or tracking
✅ Metadata file created (`fdroid-metadata.yml`)

## Submission Steps

### 1. Create a Git Tag for v1.0.0

Before submitting, you need to tag your release:

```bash
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

### 2. Fork F-Droid Data Repository

1. Go to https://gitlab.com/fdroid/fdroiddata
2. Click "Fork" button
3. Clone your fork:
   ```bash
   git clone https://gitlab.com/YOUR_USERNAME/fdroiddata.git
   cd fdroiddata
   ```

### 3. Create Metadata File

1. Create the metadata directory:
   ```bash
   mkdir -p metadata/com.musicassistant.music_assistant
   ```

2. Copy the metadata file from this repo to F-Droid format:
   ```bash
   # Copy content from fdroid-metadata.yml to:
   metadata/com.musicassistant.music_assistant.yml
   ```

### 4. Submit Merge Request

1. Create a new branch:
   ```bash
   git checkout -b add-assistant-to-the-music
   ```

2. Add and commit:
   ```bash
   git add metadata/com.musicassistant.music_assistant.yml
   git commit -m "New app: Assistant To The Music"
   ```

3. Push to your fork:
   ```bash
   git push origin add-assistant-to-the-music
   ```

4. Go to https://gitlab.com/fdroid/fdroiddata/-/merge_requests/new
5. Select your branch and create the merge request

### 5. Wait for Review

- F-Droid maintainers will review your submission
- They may request changes or ask questions
- Approval can take a few weeks
- Once approved, your app will be built and published to F-Droid

## Alternative: Faster Distribution

If you want faster availability, you can:

1. **Use IzzyOnDroid** - Faster approval, less strict requirements
   - Submit at: https://gitlab.com/IzzyOnDroid/repo/-/issues

2. **Create your own F-Droid repository** - Full control
   - Users add your repo URL to F-Droid client
   - You build and host the APKs yourself

## Need Help?

- F-Droid docs: https://f-droid.org/docs/Submitting_to_F-Droid/
- F-Droid forum: https://forum.f-droid.org/
- Your GitHub issues: https://github.com/CollotsSpot/Assistant-To-The-Music/issues
