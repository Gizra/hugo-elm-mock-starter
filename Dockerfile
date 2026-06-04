FROM --platform=linux/amd64 hugomods/hugo:exts-0.154.5

# Install Chromium and dependencies for pa11y/Puppeteer (accessibility checks).
RUN apk add --no-cache \
  chromium \
  nss \
  freetype \
  harfbuzz \
  ca-certificates \
  ttf-freefont

# Tell Puppeteer to use the installed Chromium.
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# Install Elm 0.19.1 to compile the embedded app in-container (local dev only;
# the gh-pages build ships the committed elm-main.js). The official Elm binary
# is glibc-linked, so Alpine/musl needs gcompat to run it.
RUN apk add --no-cache gcompat \
  && npm install -g elm@latest \
  && elm --version

WORKDIR /src

# Copy root package files first for layer caching.
COPY package.json package-lock.json* ./

# Copy CSS package files (Tailwind CLI lives in assets/css).
COPY assets/css/package.json assets/css/package-lock.json* ./assets/css/

# Install both root and CSS dependencies.
RUN npm install && cd assets/css && npm install

ENV PATH="/src/assets/css/node_modules/.bin:/src/node_modules/.bin:${PATH}"

# Copy the rest of the project.
COPY . .

EXPOSE 1313

CMD ["hugo", "server", "--bind", "0.0.0.0", "--baseURL", "http://localhost:1313", "--disableFastRender"]
