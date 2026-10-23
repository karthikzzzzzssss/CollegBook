import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/native_bridge.dart';
import '../../core/native_dialog.dart';
import '../home/college_guide_api.dart';
import 'contact_us_page.dart';
import 'legal_content.dart';

// Design tokens shared with the As a Mentor screen.
const _primary = Color(0xFF004D40);
const _primarySoft = Color(0xFFE0FFC2);
const _pageBg = Color(0xFFF4F7F6);
const _cardBorder = Color(0xFFE6ECEA);
const _ink = Color(0xFF1C1E21);
const _label = Color(0xFF374151);
const _muted = Color(0xFF6B7280);
const _hint = Color(0xFF9CA3AF);
const _fieldBorder = Color(0xFFDCE3E0);
const _fieldFill = Color(0xFFFAFBFB);
const _error = Color(0xFFD93025);

/// The "degree" values the API accepts.
const _degrees = ['DNB', 'Diploma', 'M.Ch', 'MD', 'MS', 'Nbems DMRD'];

/// The least a mentor may charge per minute.
const _minPerMinute = 10;

typedef _Expert = ({int id, String name});

enum _Field {
  photo,
  name,
  speciality,
  designation,
  degree,
  state,
  institute,
  experts,
  fee,
}

/// Mentor registration: photo, name, speciality, designation, degree, exam
/// type, state, institute, expertise and per-minute fee, posted as multipart
/// to college/counsellor/ (the native CounselorRegistrationActivity's
/// request). Pops true once the application is submitted.
class MentorRegistrationPage extends StatefulWidget {
  const MentorRegistrationPage({super.key, required this.api});

  final CollegeGuideApiRepository api;

  @override
  State<MentorRegistrationPage> createState() => _MentorRegistrationPageState();
}

class _MentorRegistrationPageState extends State<MentorRegistrationPage> {
  final _scroll = ScrollController();
  final _name = TextEditingController();
  final _fee = TextEditingController();
  final _nameFocus = FocusNode();
  final _feeFocus = FocusNode();
  final _keys = {for (final f in _Field.values) f: GlobalKey()};

  Uint8List? _photo;
  String? _speciality;
  String? _designation;
  String? _degree;
  String? _state;
  String? _institute;
  List<_Expert> _experts = const [];

  /// Inline messages, shown once Submit has been tried.
  final Map<_Field, String> _errors = {};
  bool _triedSubmit = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _fee.addListener(_changed);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _name.dispose();
    _fee.dispose();
    _nameFocus.dispose();
    _feeFocus.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    if (_triedSubmit) _validate();
  });

  void _set(VoidCallback change) {
    change();
    _changed();
  }

  bool get _hasInput =>
      _photo != null ||
      _name.text.trim().isNotEmpty ||
      _fee.text.trim().isNotEmpty ||
      _speciality != null ||
      _designation != null ||
      _degree != null ||
      _state != null ||
      _institute != null ||
      _experts.isNotEmpty;

  /// Back with a half-filled form asks before throwing it away.
  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop || _submitting) return;
    final discard = await showNativeAlert(
      context,
      title: 'Discard application?',
      message: 'The details you have entered will be lost.',
      positive: 'Discard',
      negative: 'Keep editing',
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  // ---- validation ----

  /// Fills [_errors] (in form order) for every missing or invalid field.
  void _validate() {
    _errors.clear();
    if (_photo == null) _errors[_Field.photo] = 'Please add a profile photo';
    if (_name.text.trim().isEmpty) {
      _errors[_Field.name] = 'Please enter your name';
    }
    if (_speciality == null) {
      _errors[_Field.speciality] = 'Please select your speciality';
    }
    if (_designation == null) {
      _errors[_Field.designation] = 'Please select your designation';
    }
    if (_degree == null) _errors[_Field.degree] = 'Please select your degree';
    if (_state == null) _errors[_Field.state] = 'Please select a state';
    if (_institute == null) {
      _errors[_Field.institute] = 'Please select your institute';
    }
    if (_experts.isEmpty) {
      _errors[_Field.experts] = 'Please select your expertise';
    }
    final fee = _fee.text.trim();
    final value = double.tryParse(fee);
    if (fee.isEmpty) {
      _errors[_Field.fee] = 'Please enter your fee per minute';
    } else if (value == null) {
      _errors[_Field.fee] = 'Enter a valid amount';
    } else if (value < _minPerMinute) {
      _errors[_Field.fee] = 'Fee should be at least ₹$_minPerMinute per minute';
    }
  }

  // ---- photo ----

  Future<void> _choosePhoto() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetFrame(
        title: 'Profile photo',
        subtitle: 'Use a clear, recent photo of your face.',
        children: [
          _SheetAction(
            icon: Icons.photo_library_outlined,
            label: 'Choose from gallery',
            onTap: (c) => Navigator.of(c).pop(ImageSource.gallery),
          ),
          _SheetAction(
            icon: Icons.photo_camera_outlined,
            label: 'Take a photo',
            onTap: (c) => Navigator.of(c).pop(ImageSource.camera),
          ),
        ],
      ),
    );
    if (source == null) return;
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        requestFullMetadata: false,
      );
    } on Exception {
      if (mounted && source == ImageSource.camera) {
        showToast(context, 'Camera not available');
      }
      return;
    }
    if (picked == null) return;
    // A square crop, so the round avatar shows exactly what was chosen.
    final CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 1000,
        maxHeight: 1000,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: _primary,
            statusBarLight: false,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: _primary,
            backgroundColor: Colors.black,
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.square,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
          IOSUiSettings(
            title: 'Crop photo',
            cropStyle: CropStyle.circle,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            aspectRatioPresets: const [CropAspectRatioPreset.square],
          ),
        ],
      );
    } on Exception {
      if (mounted) showToast(context, "Couldn't crop that image");
      return;
    }
    // Backing out of the cropper keeps the current photo.
    if (cropped == null) return;
    final bytes = await cropped.readAsBytes();
    // A JPEG no larger than 1000px a side.
    final jpeg = await compute(_shrink, bytes);
    if (!mounted) return;
    if (jpeg == null) {
      showToast(context, "Couldn't read that image");
      return;
    }
    _set(() => _photo = jpeg);
  }

  // ---- pickers ----

  Future<void> _pick(
    String title,
    String endpoint,
    String? selected,
    ValueChanged<String> onPicked, {
    Map<String, String> query = const {},
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _OptionPickerPage(
          api: widget.api,
          title: title,
          endpoint: endpoint,
          query: query,
          selected: selected,
        ),
      ),
    );
    if (picked != null && mounted) _set(() => onPicked(picked));
  }

  Future<void> _chooseDegree() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _SheetFrame(
        title: 'Select degree',
        children: [
          for (final d in _degrees)
            _SheetAction(
              label: d,
              selected: d == _degree,
              onTap: (c) => Navigator.of(c).pop(d),
            ),
        ],
      ),
    );
    if (picked != null) _set(() => _degree = picked);
  }

  void _chooseInstitute() {
    if (_state == null) {
      showToast(context, 'Please select state first');
      return;
    }
    _pick(
      'Select institute',
      'college/counsellor/drop-down/institute_name/',
      _institute,
      (v) => _institute = v,
      query: {'state': _state!},
    );
  }

  Future<void> _chooseExperts() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await Navigator.of(context).push<List<_Expert>>(
      MaterialPageRoute(
        builder: (_) => _ExpertsPickerPage(api: widget.api, selected: _experts),
      ),
    );
    if (result != null && mounted) _set(() => _experts = result);
  }

  // ---- submit ----

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _triedSubmit = true;
      _validate();
    });
    if (_errors.isNotEmpty) {
      final first = _errors.keys.first;
      showToast(context, _errors[first]!);
      final target = _keys[first]!.currentContext;
      if (target != null) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      if (first == _Field.name) _nameFocus.requestFocus();
      if (first == _Field.fee) _feeFocus.requestFocus();
      return;
    }
    setState(() => _submitting = true);
    String message;
    var ok = false;
    try {
      final result = await widget.api.postMultipart(
        'college/counsellor/',
        fields: {
          'name': _name.text.trim(),
          'state': _state!,
          'institute_name': _institute!,
          'speciality': _speciality!,
          'designation': _designation!,
          'degree': _degree!,
          'expert': '[${_experts.map((e) => e.id).join(',')}]',
          'per_min': _fee.text.trim(),
          'exam_type': 'NEET_PG',
        },
        files: [
          http.MultipartFile.fromBytes(
            'image',
            _photo!,
            filename: 'mentor_profile.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        ],
      );
      final json = result.json;
      ok = result.status >= 200 && result.status < 300;
      message =
          '${json?['description'] ?? json?['message'] ?? (ok ? 'Registration submitted' : 'Something went wrong')}';
    } on CollegeGuideApiException {
      message = 'Network error. Please try again.';
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    showToast(context, message);
    if (ok) Navigator.of(context).pop(true);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: !_submitting && !_hasInput,
        onPopInvokedWithResult: _onPop,
        child: Scaffold(
          backgroundColor: _primary,
          body: SafeArea(
            bottom: false,
            child: ColoredBox(
              color: _pageBg,
              child: Column(
                children: [
                  const _Header(),
                  Expanded(
                    child: ListView(
                      key: const Key('mentorRegistrationList'),
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        const _IntroCard(),
                        const SizedBox(height: 16),
                        _photoCard(),
                        const SizedBox(height: 12),
                        _Section(
                          title: 'Professional details',
                          subtitle: 'How students will see you',
                          children: [
                            _TextInput(
                              key: _keys[_Field.name],
                              label: 'Full name',
                              hint: 'e.g. Dr. Ananya Rao',
                              controller: _name,
                              focusNode: _nameFocus,
                              error: _errors[_Field.name],
                              inputKey: const Key('mentorName'),
                              capitalization: TextCapitalization.words,
                            ),
                            _SelectInput(
                              key: _keys[_Field.speciality],
                              label: 'Speciality',
                              hint: 'Select speciality',
                              value: _speciality,
                              error: _errors[_Field.speciality],
                              onTap: () => _pick(
                                'Select speciality',
                                'college/counsellor/drop-down/speciality/',
                                _speciality,
                                (v) => _speciality = v,
                              ),
                            ),
                            _SelectInput(
                              key: _keys[_Field.designation],
                              label: 'Designation',
                              hint: 'Select designation',
                              value: _designation,
                              error: _errors[_Field.designation],
                              onTap: () => _pick(
                                'Select designation',
                                'college/counsellor/drop-down/designation/',
                                _designation,
                                (v) => _designation = v,
                              ),
                            ),
                            _SelectInput(
                              key: _keys[_Field.degree],
                              label: 'Degree',
                              hint: 'Select degree',
                              value: _degree,
                              error: _errors[_Field.degree],
                              sheet: true,
                              onTap: _chooseDegree,
                            ),
                            const _SelectInput(
                              label: 'Exam type',
                              hint: '',
                              value: 'NEET PG',
                              locked: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Section(
                          title: 'Your institute',
                          subtitle: 'Where you study or work now',
                          children: [
                            _SelectInput(
                              key: _keys[_Field.state],
                              label: 'State',
                              hint: 'Select state',
                              value: _state,
                              error: _errors[_Field.state],
                              onTap: () => _pick(
                                'Select state',
                                'college/counsellor/drop-down/state/',
                                _state,
                                (v) {
                                  // The institute list depends on the state.
                                  if (v != _state) _institute = null;
                                  _state = v;
                                },
                              ),
                            ),
                            _SelectInput(
                              key: _keys[_Field.institute],
                              label: 'Institute',
                              hint: _state == null
                                  ? 'Select a state first'
                                  : 'Select institute',
                              value: _institute,
                              error: _errors[_Field.institute],
                              disabled: _state == null,
                              onTap: _chooseInstitute,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Section(
                          title: 'Areas of expertise',
                          subtitle: 'Topics you can guide students on',
                          children: [
                            _ExpertsInput(
                              key: _keys[_Field.experts],
                              experts: _experts,
                              error: _errors[_Field.experts],
                              onEdit: _chooseExperts,
                              onRemove: (e) => _set(
                                () => _experts = [
                                  for (final x in _experts)
                                    if (x.id != e.id) x,
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _Section(
                          title: 'Consultation fee',
                          subtitle: 'Students are charged per minute of call',
                          children: [
                            _TextInput(
                              key: _keys[_Field.fee],
                              label: 'Fee per minute',
                              hint: '$_minPerMinute',
                              controller: _fee,
                              focusNode: _feeFocus,
                              error: _errors[_Field.fee],
                              inputKey: const Key('mentorPerMin'),
                              prefix: '₹',
                              suffix: '/ min',
                              numeric: true,
                              helper:
                                  'Minimum ₹$_minPerMinute per minute. You can change it later.',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _SubmitBar(
                    submitting: _submitting,
                    onSubmit: _submit,
                    onTerms: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const LegalDocumentPage(doc: LegalDoc.terms),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoCard() {
    final error = _errors[_Field.photo];
    return Container(
      key: _keys[_Field.photo],
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(error: error != null),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _photo == null
                ? 'Add profile photo'
                : 'Change profile photo',
            child: GestureDetector(
              onTap: _choosePhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F4),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: error != null ? _error : Colors.white,
                        width: 3,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _photo == null
                        ? const Icon(
                            Icons.person_rounded,
                            size: 44,
                            color: Color(0xFFB7C0C7),
                          )
                        : Image.memory(_photo!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        _photo == null
                            ? Icons.add_a_photo_outlined
                            : Icons.edit_outlined,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Profile photo',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  error ??
                      'A clear photo helps students recognise and trust you.',
                  style: TextStyle(
                    color: error != null ? _error : _muted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: _choosePhoto,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _photo == null ? 'Upload photo' : 'Change photo',
                      style: const TextStyle(
                        color: _primary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration({bool error = false}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: error ? const Color(0xFFF3B9B4) : _cardBorder),
);

/// Green app bar with back, title, help and a completion meter.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _primary,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Semantics(
                  label: 'Back',
                  button: true,
                  child: InkResponse(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Become a Mentor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Semantics(
                  label: 'Help',
                  button: true,
                  child: InkResponse(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ContactUsPage(),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.help_outline_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _primarySoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xE6FFFFFF),
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E4B3E), _primary],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Color(0x26FFFFFF),
                  shape: BoxShape.circle,
                ),
                child: SvgPicture.asset(
                  'assets/icons/ic_menu_mentor.svg',
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guide NEET PG aspirants',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Earn on your own schedule',
                      style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          point(
            Icons.videocam_outlined,
            '1:1 video consultations with students',
          ),
          point(
            Icons.currency_rupee_rounded,
            'You set your own per-minute fee',
          ),
          point(Icons.verified_outlined, 'Verified mentor badge on approval'),
        ],
      ),
    );
  }
}

/// A white card with a section title and its fields.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// Field label above a box, with an inline error or helper below.
class _FieldFrame extends StatelessWidget {
  const _FieldFrame({
    required this.label,
    required this.child,
    this.error,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? error;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final note = error ?? helper;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _label,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          child,
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null)
                    const Padding(
                      padding: EdgeInsets.only(right: 4, top: 1),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: _error,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        color: error != null ? _error : _muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

BoxDecoration _boxDecoration({
  bool error = false,
  bool focused = false,
  bool disabled = false,
}) => BoxDecoration(
  color: disabled ? const Color(0xFFF2F4F5) : _fieldFill,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(
    color: error
        ? _error
        : focused
        ? _primary
        : _fieldBorder,
    width: error || focused ? 1.5 : 1,
  ),
);

class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.focusNode,
    this.error,
    this.helper,
    this.inputKey,
    this.prefix,
    this.suffix,
    this.numeric = false,
    this.capitalization = TextCapitalization.none,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final String? helper;
  final Key? inputKey;
  final String? prefix;
  final String? suffix;
  final bool numeric;
  final TextCapitalization capitalization;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const valueStyle = TextStyle(
      color: _ink,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    );
    return _FieldFrame(
      label: widget.label,
      error: widget.error,
      helper: widget.helper,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: _boxDecoration(
          error: widget.error != null,
          focused: widget.focusNode.hasFocus,
        ),
        child: Row(
          children: [
            if (widget.prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  widget.prefix!,
                  style: valueStyle.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            Expanded(
              child: TextField(
                key: widget.inputKey,
                controller: widget.controller,
                focusNode: widget.focusNode,
                cursorColor: _primary,
                textCapitalization: widget.capitalization,
                textInputAction: TextInputAction.done,
                keyboardType: widget.numeric
                    ? TextInputType.number
                    : TextInputType.name,
                inputFormatters: widget.numeric
                    ? [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ]
                    : [LengthLimitingTextInputFormatter(60)],
                style: valueStyle,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(color: _hint, fontSize: 15),
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            if (widget.suffix != null)
              Text(
                widget.suffix!,
                style: const TextStyle(color: _muted, fontSize: 14),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tappable box that opens a picker; shows the choice or a hint.
class _SelectInput extends StatelessWidget {
  const _SelectInput({
    super.key,
    required this.label,
    required this.hint,
    this.value,
    this.error,
    this.onTap,
    this.sheet = false,
    this.disabled = false,
    this.locked = false,
  });

  final String label;
  final String hint;
  final String? value;
  final String? error;
  final VoidCallback? onTap;
  final bool sheet;
  final bool disabled;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return _FieldFrame(
      label: label,
      error: error,
      child: Semantics(
        button: !locked,
        label: '$label, ${value ?? hint}',
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: locked ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: _boxDecoration(
                error: error != null,
                disabled: disabled || locked,
              ),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        hasValue ? value! : hint,
                        style: TextStyle(
                          color: hasValue ? (locked ? _muted : _ink) : _hint,
                          fontSize: 15,
                          fontWeight: hasValue
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      locked
                          ? Icons.lock_outline_rounded
                          : sheet
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: locked ? 18 : 24,
                      color: disabled || locked ? _hint : _muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selected expertise as removable chips, plus an add/edit chip.
class _ExpertsInput extends StatelessWidget {
  const _ExpertsInput({
    super.key,
    required this.experts,
    required this.error,
    required this.onEdit,
    required this.onRemove,
  });

  final List<_Expert> experts;
  final String? error;
  final VoidCallback onEdit;
  final ValueChanged<_Expert> onRemove;

  @override
  Widget build(BuildContext context) {
    return _FieldFrame(
      label: 'Expertise',
      error: error,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: _boxDecoration(error: error != null),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final e in experts)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F2ED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        e.name,
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      label: 'Remove ${e.name}',
                      button: true,
                      child: InkResponse(
                        onTap: () => onRemove(e),
                        radius: 14,
                        child: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: _primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: _primary),
              ),
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        experts.isEmpty
                            ? Icons.add_rounded
                            : Icons.edit_outlined,
                        size: 16,
                        color: _primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        experts.isEmpty ? 'Add expertise' : 'Edit',
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sticky bottom bar: Submit and the terms note.
class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.submitting,
    required this.onSubmit,
    required this.onTerms,
  });

  final bool submitting;
  final VoidCallback onSubmit;
  final VoidCallback onTerms;

  @override
  Widget build(BuildContext context) {
    const buttonText = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    );
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const Key('mentorSubmit'),
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: _primary,
                disabledBackgroundColor: const Color(0xFF5E8A82),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: submitting
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Submitting…', style: buttonText),
                      ],
                    )
                  : const Text('Submit application', style: buttonText),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onTerms,
            child: const Text.rich(
              TextSpan(
                text: 'By submitting, you agree to our ',
                children: [
                  TextSpan(
                    text: 'Terms & Conditions',
                    style: TextStyle(
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded bottom sheet with a grab handle, title and rows.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: 12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD3DED9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                subtitle!,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final void Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFE6F2ED),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: _primary),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? _primary : _ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_rounded, color: _primary, size: 22),
          ],
        ),
      ),
    );
  }
}

/// ≤1000px JPEG at quality 85, or null if it can't be decoded.
Uint8List? _shrink(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  image = img.bakeOrientation(image);
  final side = image.width > image.height ? image.width : image.height;
  if (side > 1000) {
    image = image.width >= image.height
        ? img.copyResize(image, width: 1000)
        : img.copyResize(image, height: 1000);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Shared picker chrome: green header with a rounded search box, then a list.
class _PickerScaffold extends StatelessWidget {
  const _PickerScaffold({
    required this.title,
    required this.onSearch,
    required this.body,
    this.bottom,
  });

  final String title;
  final ValueChanged<String> onSearch;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder none() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _primary,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _primary,
        body: SafeArea(
          bottom: false,
          child: ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  color: _primary,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 56,
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Semantics(
                              label: 'Back',
                              button: true,
                              child: InkResponse(
                                onTap: () => Navigator.of(context).maybePop(),
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          height: 46,
                          child: TextField(
                            key: const Key('pickerSearch'),
                            onChanged: onSearch,
                            cursorColor: _primary,
                            style: const TextStyle(color: _ink, fontSize: 15),
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: const TextStyle(
                                color: _hint,
                                fontSize: 15,
                              ),
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                color: _muted,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              border: none(),
                              enabledBorder: none(),
                              focusedBorder: none(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: body),
                if (bottom != null)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: _cardBorder)),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: bottom,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _pickRow(
  String name,
  bool checked,
  VoidCallback onTap, {
  bool multi = false,
}) => InkWell(
  onTap: onTap,
  child: Container(
    constraints: const BoxConstraints(minHeight: 54),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFF0F2F2))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              name,
              style: TextStyle(
                color: checked ? _primary : _ink,
                fontSize: 15,
                fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (multi)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: checked ? _primary : const Color(0xFFC7CBD1),
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : null,
          )
        else if (checked)
          const Icon(Icons.check_rounded, color: _primary, size: 22),
      ],
    ),
  ),
);

Widget _pickerMessage(IconData icon, String text) => Center(
  child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: _hint),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 14),
        ),
      ],
    ),
  ),
);

List<_Expert> _items(Map<String, dynamic> json) {
  final data = json['data'] is Map ? json['data'] as Map : const {};
  return [
    for (final r in (data['results'] as List? ?? const []))
      if (r is Map && r['name'] != null)
        (id: (r['id'] as num?)?.toInt() ?? 0, name: '${r['name']}'),
  ];
}

/// Single-select options (speciality, designation, state, institute):
/// tapping a row returns its name.
class _OptionPickerPage extends StatefulWidget {
  const _OptionPickerPage({
    required this.api,
    required this.title,
    required this.endpoint,
    required this.query,
    required this.selected,
  });

  final CollegeGuideApiRepository api;
  final String title;
  final String endpoint;
  final Map<String, String> query;
  final String? selected;

  @override
  State<_OptionPickerPage> createState() => _OptionPickerPageState();
}

class _OptionPickerPageState extends State<_OptionPickerPage> {
  List<_Expert>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    widget.api
        .send('GET', widget.endpoint, query: widget.query)
        .then(_items)
        .catchError((Object _) => <_Expert>[])
        .then((items) {
          if (mounted) setState(() => _all = items);
        });
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final shown = [
      for (final i in all ?? const <_Expert>[])
        if (_query.isEmpty || i.name.toLowerCase().contains(_query)) i,
    ];
    return _PickerScaffold(
      title: widget.title,
      onSearch: (q) => setState(() => _query = q.trim().toLowerCase()),
      body: all == null
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : all.isEmpty
          ? _pickerMessage(Icons.inbox_outlined, 'Nothing to show right now')
          : shown.isEmpty
          ? _pickerMessage(
              Icons.search_off_rounded,
              'No matches for your search',
            )
          : ListView(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                for (final i in shown)
                  _pickRow(
                    i.name,
                    i.name == widget.selected,
                    () => Navigator.of(context).pop(i.name),
                  ),
              ],
            ),
    );
  }
}

/// Multi-select expertise over the paged list; pops the chosen items.
class _ExpertsPickerPage extends StatefulWidget {
  const _ExpertsPickerPage({required this.api, required this.selected});

  final CollegeGuideApiRepository api;
  final List<_Expert> selected;

  @override
  State<_ExpertsPickerPage> createState() => _ExpertsPickerPageState();
}

class _ExpertsPickerPageState extends State<_ExpertsPickerPage> {
  static const _pageSize = 50;

  final _scroll = ScrollController();
  final List<_Expert> _all = [];
  late final Map<int, _Expert> _selected = {
    for (final e in widget.selected) e.id: e,
  };
  String _query = '';
  int _page = 1;
  bool _hasNext = true;
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasNext) return;
    setState(() => _loading = true);
    try {
      final json = await widget.api.send(
        'GET',
        'college/counsellor-expert/',
        query: {'page': '$_page', 'limit': '$_pageSize'},
      );
      final data = json['data'] is Map ? json['data'] as Map : const {};
      _hasNext = data['next'] == true;
      _page++;
      _all.addAll(_items(json));
    } on CollegeGuideApiException {
      _hasNext = false;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _loadedOnce = true;
      });
    }
  }

  void _done() {
    if (_selected.isEmpty) {
      showToast(context, 'Please select at least one');
      return;
    }
    Navigator.of(context).pop(_selected.values.toList());
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final i in _all)
        if (_query.isEmpty || i.name.toLowerCase().contains(_query)) i,
    ];
    final count = _selected.length;
    return _PickerScaffold(
      title: 'Select expertise',
      onSearch: (q) => setState(() => _query = q.trim().toLowerCase()),
      body: !_loadedOnce
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : _all.isEmpty
          ? _pickerMessage(Icons.inbox_outlined, 'Nothing to show right now')
          : shown.isEmpty
          ? _pickerMessage(
              Icons.search_off_rounded,
              'No matches for your search',
            )
          : ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final i in shown)
                  _pickRow(
                    i.name,
                    _selected.containsKey(i.id),
                    () => setState(() {
                      if (_selected.remove(i.id) == null) _selected[i.id] = i;
                    }),
                    multi: true,
                  ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      bottom: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: _done,
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            count > 0 ? 'Done · $count selected' : 'Done',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
