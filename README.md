# Virtual TWAIN Scanner for Windows 11 ARM64

This project builds a small virtual TWAIN data source without Visual Studio.
It is aimed at a Windows 11 ARM64 VM running in UTM.

## Important architecture note

TWAIN data sources are loaded into the scanner application process, so the
data source architecture must match the application architecture.

- x64 TWAIN app on Windows ARM64 emulation: build `x86_64` and install to
  `C:\Windows\twain_64`.
- x86 TWAIN app on Windows ARM64 emulation: build `i686` and install to
  `C:\Windows\twain_32`.
- native ARM64 TWAIN app: use the `arm64` installer. It installs an ARM64 `.ds`
  into `C:\Windows\twain_64`.

The 64-bit DSM is `twaindsm.dll`. It is not the old built-in `twain_32.dll`.
The DSM discovers data sources by loading `.ds` files from the TWAIN folders.

## Build without Visual Studio

Recommended: build inside the Windows VM with MSYS2 UCRT64.

1. Install MSYS2 from <https://www.msys2.org/>.
2. Open the "MSYS2 UCRT64" shell.
3. Install the compiler:

   ```sh
   pacman -S --needed mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gcc-libs make
   ```

4. From this project directory:

   ```sh
   make
   ```

The output will be:

```text
build/x64/VirtualScanner.ds
```

For native ARM64 experimentation, install the ARM64 MinGW toolchain and run:

```sh
make CC=clang TARGET=aarch64-w64-windows-gnu
```

You will still need a native ARM64 `twaindsm.dll` and a native ARM64 TWAIN app
to use that build.

## Install in the VM

Run PowerShell as Administrator:

```powershell
.\scripts\install.ps1
```

Also install `twaindsm.dll` into `C:\Windows\System32` if your TWAIN app does
not already ship it. Use the 64-bit/x64 build of the DSM for x64 apps.

## Test

Use ExamView Test Manager or a TWAIN test app such as TWACKER.

Expected behavior:

1. The source list contains `Virtual Scanner`.
2. If the scanner inbox is empty, the `Virtual Scanner Inbox` helper opens.
3. Add PNG/JPG/TIFF/PDF files in the helper, then click `Scan`.
4. ExamView receives the queued pages through TWAIN.

For ExamView on Windows 11 ARM64, the `x86` installer is usually the right one
because ExamView is normally a 32-bit application.

## Build with Google Cloud Build

Cloud Build can produce the TWAIN data source and Windows installers from a
Linux build container. The build uses LLVM-MinGW and NSIS, not Visual Studio.

These commands assume you are running from macOS Terminal on the Mac host.

### 1. Install Google Cloud CLI from scratch

Install the current Google Cloud CLI archive for your Mac:

```sh
cd "$HOME"

case "$(uname -m)" in
  arm64)
    GCLOUD_TAR="google-cloud-cli-darwin-arm.tar.gz"
    ;;
  x86_64)
    GCLOUD_TAR="google-cloud-cli-darwin-x86_64.tar.gz"
    ;;
  *)
    echo "Unsupported Mac architecture: $(uname -m)"
    exit 1
    ;;
esac

curl -O "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/${GCLOUD_TAR}"
tar -xf "${GCLOUD_TAR}"
./google-cloud-sdk/install.sh
```

Close and reopen Terminal, or reload your shell:

```sh
exec -l "$SHELL"
```

Check that `gcloud` runs:

```sh
gcloud version
```

If `gcloud` complains that it is using Python 3.9, clear the old Python override:

```sh
unset CLOUDSDK_PYTHON
sed -i '' '/CLOUDSDK_PYTHON/d' "$HOME/.zshrc" "$HOME/.zprofile" 2>/dev/null || true
exec -l "$SHELL"
gcloud version
```

If it still complains about Python, install a supported Python and point
`gcloud` at it:

```sh
brew install python@3.12
export CLOUDSDK_PYTHON="$(brew --prefix python@3.12)/bin/python3.12"
echo "export CLOUDSDK_PYTHON=\"$(brew --prefix python@3.12)/bin/python3.12\"" >> "$HOME/.zshrc"
gcloud version
```

### 2. Sign in and choose a Google Cloud project

Start the normal browser sign-in flow:

```sh
gcloud init
```

If you already have a Google Cloud project, set it like this:

```sh
PROJECT_ID="your-existing-project-id"
gcloud config set project "${PROJECT_ID}"
```

If you need to create a brand-new project, use these commands. Billing must be
enabled for Cloud Build to run.

```sh
PROJECT_ID="virtual-scanner-$(date +%Y%m%d%H%M%S)"

gcloud projects create "${PROJECT_ID}" --name="Virtual Scanner"
gcloud config set project "${PROJECT_ID}"

gcloud billing accounts list
```

Copy the billing account ID from the `ACCOUNT_ID` column, then run:

```sh
BILLING_ACCOUNT_ID="paste-your-billing-account-id-here"
gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT_ID}"
```

### 3. Enable the required Google Cloud APIs

```sh
gcloud services enable cloudbuild.googleapis.com
gcloud services enable storage.googleapis.com
```

### 4. Create the artifact bucket

Google Cloud Storage bucket names must be lowercase, and they cannot contain
underscores. Use `virtual-scanner`, not `VIRTUAL_SCANNER`.

```sh
BUCKET="virtual-scanner"
gcloud storage buckets create "gs://${BUCKET}" --location=us-central1 --uniform-bucket-level-access
```

Bucket names are global across all Google Cloud users. If that exact name is
already taken, use this project-specific name instead:

```sh
BUCKET="${PROJECT_ID}-virtual-scanner"
gcloud storage buckets create "gs://${BUCKET}" --location=us-central1 --uniform-bucket-level-access
```

Grant the Cloud Build default service account permission to write artifacts to
the bucket:

```sh
BUILD_SA="$(gcloud builds get-default-service-account)"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="serviceAccount:${BUILD_SA}" \
  --role="roles/storage.objectAdmin"
```

### 5. Build the installers

Run this from the project folder on your Mac:

```sh
cd "$HOME/Documents/virtual-scanner"

VERSION="1.5.1"
gcloud builds submit . \
  --config cloudbuild.yaml \
  --substitutions "_ARTIFACT_BUCKET=${BUCKET},_VERSION=${VERSION}"
```

When the build succeeds, the output ends with a table like this:

```text
DONE
--------------------------------------------------------------------------------
ID                                    CREATE_TIME                DURATION  STATUS
BUILD_ID_HERE                         ...                        ...       SUCCESS
```

Save the latest build ID:

```sh
BUILD_ID="$(gcloud builds list --limit=1 --format='value(ID)')"
echo "${BUILD_ID}"
```

Cloud Build stores the artifacts here:

```text
gs://BUCKET/virtual-scanner/BUILD_ID/
```

### 6. Download the ExamView installer

ExamView is usually a 32-bit application, even inside Windows 11 ARM64. For
that setup, download the x86 installer:

```sh
gcloud storage cp \
  "gs://${BUCKET}/virtual-scanner/${BUILD_ID}/VirtualScanner-${VERSION}-x86-setup.exe" \
  .
```

Copy this file into the Windows 11 ARM64 VM and run it as Administrator:

```text
VirtualScanner-1.5.1-x86-setup.exe
```

Use `x86` if ExamView is installed under `C:\Program Files (x86)`. Use `x64`
if the TWAIN app is a 64-bit Intel app. Use `arm64` only for a native ARM64
TWAIN app.

Other generated files are also available:

```text
VirtualScanner-1.5.1-arm64-setup.exe
VirtualScanner-1.5.1-x64-setup.exe
VirtualScanner-1.5.1-x86-setup.exe
VirtualScanner-1.5.1-arm64-portable.zip
VirtualScanner-1.5.1-x64-portable.zip
VirtualScanner-1.5.1-x86-portable.zip
```

The portable ZIP avoids the installer executable. Extract it in the VM, open
PowerShell as Administrator in that extracted folder, and run:

```powershell
.\install-portable.ps1 -Arch x86
```

Run either the installer or the portable installer as Administrator inside the
Windows 11 ARM64 VM.

The installer also adds a desktop and Start Menu shortcut:

```text
Virtual Scanner Inbox
```

Use that small app to add PNG/JPG/TIFF/PDF files to the scanner inbox without
opening the folder manually.

If ExamView starts a scan while the inbox is empty, the scanner launches this
helper app and keeps the TWAIN session open. Add files, then click
`Scan` in the helper app; ExamView will continue the scan.

## Folder Scanner Mode

The installer creates this inbox:

```text
C:\Users\Public\Documents\VirtualScannerInbox
```

Put image files there before scanning in ExamView. Supported formats are:

```text
PNG, JPG, JPEG, BMP, TIF, TIFF
```

When ExamView scans, the TWAIN source imports the first supported image
alphabetically. After ExamView completes the transfer, that file is moved to:

```text
C:\Users\Public\Documents\VirtualScannerInbox\Scanned\yyyyMMdd-HHmmss-fff
```

Each transferred image goes into a timestamped folder so separate scan runs stay
grouped and do not overwrite each other.

PDF files are also supported when Ghostscript is installed in the Windows VM.
Install it with winget:

```powershell
winget install ArtifexSoftware.Ghostscript
```

Then place a PDF in the inbox. If no image files are waiting, the scanner will
render the first PDF alphabetically into 300 DPI PNG pages, move the PDF to
the current timestamped `Scanned` folder, and feed the generated PNG pages in
order. Those generated PNG pages are also moved into that same timestamped
folder as ExamView consumes them.

If Ghostscript is installed somewhere unusual, set:

```powershell
[Environment]::SetEnvironmentVariable(
  "VIRTUAL_SCANNER_GHOSTSCRIPT",
  "C:\Path\To\gswin64c.exe",
  "Machine"
)
```

Restart ExamView after changing that environment variable.
