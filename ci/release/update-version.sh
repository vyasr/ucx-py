#!/bin/bash
########################
# ucx-py Version Updater #
########################

## Usage
# bash update-version.sh <new_version>


# Format is Major.Minor.Patch - no leading 'v' or trailing 'a'
# Example: 0.30.00
NEXT_FULL_TAG=$1

# Get current version
CURRENT_TAG=$(git tag | grep -xE 'v[0-9\.]+' | sort --version-sort | tail -n 1 | tr -d 'v')
CURRENT_MAJOR=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[1]}')
CURRENT_MINOR=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[2]}')
CURRENT_PATCH=$(echo $CURRENT_TAG | awk '{split($0, a, "."); print a[3]}')
CURRENT_SHORT_TAG=${CURRENT_MAJOR}.${CURRENT_MINOR}

#Get <major>.<minor> for next version
NEXT_MAJOR=$(echo $NEXT_FULL_TAG | awk '{split($0, a, "."); print a[1]}')
NEXT_MINOR=$(echo $NEXT_FULL_TAG | awk '{split($0, a, "."); print a[2]}')
NEXT_SHORT_TAG=${NEXT_MAJOR}.${NEXT_MINOR}

# Get RAPIDS version associated w/ ucx-py version
NEXT_RAPIDS_SHORT_TAG="$(curl -sL https://version.gpuci.io/ucx-py/${NEXT_SHORT_TAG})"

# Need to distutils-normalize the versions for some use cases
NEXT_RAPIDS_SHORT_TAG_PEP440=$(python -c "from setuptools.extern import packaging; print(packaging.version.Version('${NEXT_RAPIDS_SHORT_TAG}'))")
NEXT_RAPIDS_FULL_TAG_PEP440=$(python -c "from setuptools.extern import packaging; print(packaging.version.Version('${NEXT_FULL_TAG}'))")

echo "Preparing release $CURRENT_TAG => $NEXT_FULL_TAG"

# Inplace sed replace; workaround for Linux and Mac
function sed_runner() {
    sed -i.bak ''"$1"'' $2 && rm -f ${2}.bak
}

DEPENDENCIES=(
  cudf
)
for FILE in dependencies.yaml; do
  for DEP in "${DEPENDENCIES[@]}"; do
    sed_runner "/-.* ${DEP}==/ s/==.*/==${NEXT_RAPIDS_SHORT_TAG_PEP440}\.*/g" ${FILE};
  done
done

for FILE in .github/workflows/*.yaml; do
  sed_runner "/shared-workflows/ s/@.*/@branch-${NEXT_RAPIDS_SHORT_TAG}/g" "${FILE}"
done

sed_runner "s/^version = .*/version = \"${NEXT_RAPIDS_FULL_TAG_PEP440}\"/g" pyproject.toml
sed_runner "s/^__version__ = .*/__version__ = \"${NEXT_RAPIDS_FULL_TAG_PEP440}\"/g" ucp/__init__.py
