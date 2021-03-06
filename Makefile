NPM_PACKAGE := $(shell node -e 'process.stdout.write(require("./package.json").name)')
NPM_VERSION := $(shell node -e 'process.stdout.write(require("./package.json").version)')

TMP_PATH    := /tmp/${NPM_PACKAGE}-$(shell date +%s)

REMOTE_NAME ?= origin
REMOTE_REPO ?= $(shell git config --get remote.${REMOTE_NAME}.url)

CURR_HEAD   := $(firstword $(shell git show-ref --hash HEAD | cut -b -6) master)
GITHUB_PROJ := nodeca/${NPM_PACKAGE}


help:
	echo "make help       - Print this help"
	echo "make lint       - Lint sources with JSHint"
	echo "make test       - Run tests"
	echo "make cover      - Create coverage report"
	echo "make doc        - Generate documentation"
	echo "make browserify - Build browserified packages"
	echo "make publish    - Set new version tag and publish npm package"


lint:
	./node_modules/.bin/eslint .


test: lint
	./node_modules/.bin/mocha


wasm:
	# see DEVELOPMENT.md for install instructions
	~/llvmwasm/bin/clang -emit-llvm --target=wasm32 -O3 -c -o ./lib/mathlib/wasm/math.bc ./lib/mathlib/wasm/math.c
	~/llvmwasm/bin/llc -asm-verbose=false -o ./lib/mathlib/wasm/math.s ./lib/mathlib/wasm/math.bc
	# --emscripten-glue needed to allow import memory object
	~/llvmwasm/binaryen/bin/s2wasm --emscripten-glue ./lib/mathlib/wasm/math.s > ./lib/mathlib/wasm/math.wast
	# Siimes nothing to optimize after clang, just use to convert wast to wasm
	~/llvmwasm/binaryen/bin/wasm-opt -O3 ./lib/mathlib/wasm/math.wast -o ./lib/mathlib/wasm/math.wasm
	rm ./lib/mathlib/wasm/math.bc
	rm ./lib/mathlib/wasm/math.s
	node ./support/wasm_wrap.js
	make browserify

wasm-emsdk:
	emcc ./lib/mathlib/wasm/math.c -v -g3 -O3 -s WASM=1 -s SIDE_MODULE=1 -o ./lib/mathlib/wasm/math.wasm
	node ./support/wasm_wrap.js
	make browserify


browserify:
	rm -rf ./dist
	mkdir dist
	# Browserify
	( printf "/* ${NPM_PACKAGE} ${NPM_VERSION} ${GITHUB_PROJ} */" ; \
		./node_modules/.bin/browserify -r ./ -s pica \
		) > dist/pica.js
	# Minify
	./node_modules/.bin/uglifyjs dist/pica.js -c -m \
		--preamble "/* ${NPM_PACKAGE} ${NPM_VERSION} ${GITHUB_PROJ} */" \
		> dist/pica.min.js


gh-pages:
	if [ "git branch --list gh-pages" ]; then \
		git branch -D gh-pages ; \
		fi
	git branch gh-pages
	git push origin gh-pages -f


publish:
	@if test 0 -ne `git status --porcelain | wc -l` ; then \
		echo "Unclean working tree. Commit or stash changes first." >&2 ; \
		exit 128 ; \
		fi
	@if test 0 -ne `git fetch ; git status | grep '^# Your branch' | wc -l` ; then \
		echo "Local/Remote history differs. Please push/pull changes." >&2 ; \
		exit 128 ; \
		fi
	@if test 0 -ne `git tag -l ${NPM_VERSION} | wc -l` ; then \
		echo "Tag ${NPM_VERSION} exists. Update package.json" >&2 ; \
		exit 128 ; \
		fi
	git tag ${NPM_VERSION} && git push origin ${NPM_VERSION}
	npm publish https://github.com/${GITHUB_PROJ}/tarball/${NPM_VERSION}


.PHONY: publish lint doc
.SILENT: help lint
