# CollegeBook

CollegeBook – by the doctor for the doctor. NEET PG college cutoffs, rank-wise
college matching, fee details, counselling choice lists, webinars and 1-to-1
video calls with PGs and faculty, for Android and iOS.

Package / bundle ID: `com.minibrain.collegebook`

## API

Debug builds use the development API (`https://dev.collegebook.app/api/v1/`)
and release builds the production API. Override it for a build with
`--dart-define=COLLEGE_GUIDE_API_BASE_URL=https://your-base-url/`.

## Run

```sh
flutter pub get
flutter run
```

## Verify

```sh
flutter analyze
flutter test
```
