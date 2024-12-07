#!/usr/bin/bash

set -eu

# This is the test file.
# It is very important.
# Data is important -> Tests are important.
# Though "some data are more important than others"

start_test() {
    local name="$1"
    echo "---- Starting test: $name ----"
    # necessary to prevent race conditions (rsync uses timestamps)
    # and doesn't go past a certain resolution
    sleep 1
}

random_file() {
    local target="$1"
    cat /dev/urandom | head -c 1024 > "$target"
}

die() {
    echo "Test failed: $1" >&2
    exit 1
}

fail() {
    echo "===================================="
    echo "+++++++++ Test failed: $1 ++++++++++" >&2
    echo "===================================="
    exit 1
    failure=1
}

validate_file() {
    local src="$1"
    local dest="$ENV/to/latest/$src"
    cmp -s "$src" "$dest" || fail "File '$file' not transferred correctly."
}

validate_file_reverse() {
    local src="$1"
    local dest="$ENV/from/$src"
    cmp -s "$src" "$dest" || fail "File '$file' not transferred correctly."
}

validate_transfer() {
    cd "$ENV/from"
    local list=()
    readarray -t list < <(find .)
    for file in "${list[@]}"; do
        if [[ -f "$file" ]]; then
            validate_file "$file"
        fi
    done
    cd -
}

validate_transfer_reverse() {
    cd "$ENV/to/latest"
    local list=()
    readarray -t list < <(find .)
    for file in "${list[@]}"; do
        if [[ -f "$file" ]]; then
            validate_file "$file"
        fi
    done
    cd -
}

declare -r PROG="$(dirname "$(readlink -f "$0")")/nana"
declare -r ENV="/tmp/chikai-test.$((RANDOM % 99999))"
failure=0

# set -x

mkdir "$ENV"
cd "$ENV"

pwd

mkdir from
mkdir to

# STARTEST Flat directory transfer FULL
start_test "Flat directory"

random_file from/a
random_file from/b
random_file from/c
"$PROG" run -a full from/ to/

# Validate
cd from
for file in *; do
    cmp -s "$file" "../to/latest/$file" || fail "File '$file' not transferred"
done
cd -

# STARTTEST Recursive directory transfer FULL
start_test "Recursive directory"

rm -r to/*

mkdir -p from/dirA/dirAA
mkdir -p from/dirA/dirAB
mkdir -p from/dirB/dirBA

random_file from/dirA/a
random_file from/dirA/b
random_file from/dirA/dirAA/a
random_file from/dirA/dirAA/b
random_file from/dirA/dirAB/a
random_file from/dirA/dirAB/b
random_file from/dirB/a
random_file from/dirB/b
random_file from/dirB/dirBA/a
random_file from/dirB/dirBA/b

"$PROG" run -a full from/ to/

validate_transfer

# STARTEST
start_test "Single modification"

target="from/dirA/a"

random_file "$target"

"$PROG" run -a inc from/ to/

validate_transfer

[[ $(stat --format='%h' "$target") -ne 1 ]] && fail "Invalid number of links for $target"

# STARTTEST
start_test "Random location"

cd /usr

"$PROG" run -a full "$ENV/from" "$ENV/to"

cd -
validate_transfer

# STARTTEST
start_test "Prune blackbox"

old_size="$(du --max-depth=0 --apparent-size to/ | grep -oP '^[0-9]+')"
db_size="$(du --max-depth=0 --apparent-size to/*.db | grep -oP '^[0-9]+')"
old_size="$((old_size - db_size))"
"$PROG" prune to/ 14K
size="$(du --max-depth=0 --apparent-size to/ | grep -oP '^[0-9]+')"
size="$((size - db_size))"
[[ $size -gt 14 ]] && fail "Prune failed to limit size (new size is $size, old size is $old_size)"
echo "$size"


# STARTTEST
start_test "Restore"

rm -r from/dirA

echo "Please select 'dirA' from the following directory listing"
echo "(press enter to continue)"
read -r
"$PROG" restore to/ from/

[[ ! -d "from/dirA" ]] && fail "Directory not transferred"

# STARRTTEST
start_test "info"

"$PROG" size to

# ENDTEST





cd

rm -r "$ENV"

if [[ $failure -eq 0 ]]; then
    echo ">>>>>>> All tests passed. <<<<<<<"
else
    echo ".......... Some tests failed ........"
fi

