if which swiftlint >/dev/null; then
swiftlint lint --config "${SRCROOT}/${PROJECT_NAME}/Resources/Other-Sources/.swiftlint.yml"
else
echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi