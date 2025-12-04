
# Check Bash version and default /bin/sh
bash --version
ls -l /bin/sh
readlink -f /bin/sh
type -a bash sh

# Permissions + encoding + shebang
ls -l lab3.sh configure-host.sh
head -3 lab3.sh
head -3 configure-host.sh
file -b lab3.sh configure-host.sh

# If Windows line endings are present:
# (output shows "CRLF" or "with CRLF line terminators")
dos2unix lab3.sh configure-host.sh

# Run explicitly with Bash (avoids dash under /bin/sh)
bash lab3.sh
bash configure-host.sh

# PATH can differ between interactive shells and sudo:
echo "$PATH"
sudo env | grep ^PATH
