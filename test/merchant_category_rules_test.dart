import 'package:arth/models/spend_map.dart';
import 'package:arth/services/merchant_category_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches a merchant regardless of case and punctuation', () {
    final rules = const MerchantCategoryRules.empty()
        .withRule('LOCAL STORE', SpendCategory.groceries);

    expect(rules.categoryFor('local store'), SpendCategory.groceries);
    expect(rules.categoryFor('Local  Store.'), SpendCategory.groceries);
    expect(rules.categoryFor('OTHER STORE'), isNull);
  });

  test('ignores merchants too short to identify a payee', () {
    final rules =
        const MerchantCategoryRules.empty().withRule('AB', SpendCategory.food);

    expect(MerchantCategoryRules.keyFor('AB'), isNull);
    expect(rules.isEmpty, isTrue);
    expect(rules.categoryFor('AB'), isNull);
  });

  test('re-teaching a merchant replaces the earlier category', () {
    final rules = const MerchantCategoryRules.empty()
        .withRule('SWIGGY', SpendCategory.groceries)
        .withRule('SWIGGY', SpendCategory.food);

    expect(rules.length, 1);
    expect(rules.categoryFor('SWIGGY'), SpendCategory.food);
  });

  test('trims the oldest rules past the cap', () {
    var rules = const MerchantCategoryRules.empty();
    for (var i = 0; i < MerchantCategoryRules.maxRules + 5; i++) {
      rules = rules.withRule('MERCHANT$i', SpendCategory.shopping);
    }

    expect(rules.length, MerchantCategoryRules.maxRules);
    expect(rules.categoryFor('MERCHANT0'), isNull); // oldest dropped
    expect(
      rules.categoryFor('MERCHANT${MerchantCategoryRules.maxRules + 4}'),
      SpendCategory.shopping,
    );
  });

  test('round-trips through JSON', () {
    final rules = const MerchantCategoryRules.empty()
        .withRule('NOBROKER', SpendCategory.rent)
        .withRule('ACKO', SpendCategory.insuranceCar);
    final restored = MerchantCategoryRules.fromJsonString(rules.toJsonString());

    expect(restored.categoryFor('NoBroker'), SpendCategory.rent);
    expect(restored.categoryFor('acko'), SpendCategory.insuranceCar);
  });

  test('a corrupt or empty blob reads as nothing taught', () {
    expect(MerchantCategoryRules.fromJsonString(null).isEmpty, isTrue);
    expect(MerchantCategoryRules.fromJsonString('').isEmpty, isTrue);
    expect(MerchantCategoryRules.fromJsonString('not json').isEmpty, isTrue);
    expect(MerchantCategoryRules.fromJsonString('[1,2]').isEmpty, isTrue);
  });
}
