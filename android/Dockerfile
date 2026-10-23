# Android build tools for bin/build: JDK 17 and Gradle from the official image, plus the Android SDK pieces
# the app needs. Built for amd64 (see bin/build).
FROM gradle:8.10.2-jdk17

ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"

RUN apt-get update && apt-get install -y --no-install-recommends unzip curl \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSLo /tmp/tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
 && unzip -q /tmp/tools.zip -d "$ANDROID_HOME/cmdline-tools" \
 && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" \
 && rm /tmp/tools.zip \
 && yes | sdkmanager --licenses >/dev/null \
 && sdkmanager "platforms;android-35" "build-tools;35.0.0"
