import 'package:collegebook/features/community/qna.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('All India is filed as AIC, alone or with a state', () {
    expect(apiTags('All india'), 'AIC');
    expect(apiTags('All india,Telangana'), 'AIC,Telangana');
    expect(apiTags('Telangana,All india'), 'Telangana,AIC');
  });

  test('state tags pass through unchanged', () {
    expect(apiTags('Telangana'), 'Telangana');
    expect(apiTags('Andhra Pradesh,Telangana'), 'Andhra Pradesh,Telangana');
  });

  test('blank and padded tags are tidied', () {
    expect(apiTags(' All india , Telangana '), 'AIC,Telangana');
    expect(apiTags('Telangana,'), 'Telangana');
  });
}
