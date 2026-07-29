import 'package:arth/models/spend_map.dart';
import 'package:arth/providers/custom_spend_categories_provider.dart';
import 'package:arth/services/secure_storage_service.dart';
import 'package:arth/services/user_scoped_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SecureStorageService.writeObserver = null;
  });

  group('turning typed text into a category id', () {
    test('a new name becomes a custom id', () {
      expect(SpendCategory.idForUserText('Income tax'), 'custom:income_tax');
    });

    test('punctuation and spacing collapse into one separator', () {
      expect(
        SpendCategory.idForUserText('  Advance   Tax -- Q2!! '),
        'custom:advance_tax_q2',
      );
    });

    test('a built-in id is reused rather than shadowed', () {
      expect(SpendCategory.idForUserText('rent'), SpendCategory.rent);
    });

    test('a built-in display name is reused rather than shadowed', () {
      expect(SpendCategory.idForUserText('Cash / ATM'), SpendCategory.cash);
      expect(SpendCategory.idForUserText('Food & dining'), SpendCategory.food);
    });

    test('text with nothing usable in it yields no id', () {
      expect(SpendCategory.idForUserText('   '), isNull);
      expect(SpendCategory.idForUserText('!!! ---'), isNull);
    });

    test('a long name is capped so the backend key limit still holds', () {
      final id = SpendCategory.idForUserText(
        'a very long category name that keeps going and going',
      )!;
      final slug = id.substring(SpendCategory.customPrefix.length);

      expect(slug.length, lessThanOrEqualTo(SpendCategory.maxCustomSlugLength));
      expect(id.length, lessThanOrEqualTo(40));
      expect(slug.endsWith('_'), isFalse);
    });

    test('case and spacing differences resolve to the same id', () {
      expect(
        SpendCategory.idForUserText('Income Tax'),
        SpendCategory.idForUserText('  income   tax '),
      );
    });
  });

  group('labelling a custom category', () {
    test('a custom id reads as words without any lookup', () {
      expect(SpendCategory.label('custom:income_tax'), 'Income tax');
      expect(SpendCategory.label('custom:tax'), 'Tax');
    });

    test('an unknown built-in id still falls back to Other', () {
      expect(SpendCategory.label('not_a_category'), 'Other');
    });

    test('custom ids are recognised as custom, built-ins are not', () {
      expect(SpendCategory.isCustom('custom:tax'), isTrue);
      for (final builtIn in SpendCategory.all) {
        expect(SpendCategory.isCustom(builtIn), isFalse);
      }
    });
  });

  group('the saved list', () {
    ProviderContainer makeContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('adding a name keeps it clickable and stores what was typed',
        () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);

      final id = await notifier.addFromUserText('Income Tax');

      expect(id, 'custom:income_tax');
      final saved = container.read(customSpendCategoriesProvider).single;
      expect(saved.id, 'custom:income_tax');
      expect(saved.label, 'Income Tax', reason: 'typed casing is preserved');
      expect(notifier.contains('custom:income_tax'), isTrue);
    });

    test('adding the same name twice does not duplicate it', () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);

      final first = await notifier.addFromUserText('Tax');
      final second = await notifier.addFromUserText('  tax  ');

      expect(first, second);
      expect(container.read(customSpendCategoriesProvider).length, 1);
    });

    test('naming a built-in does not add to the custom list', () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);

      final id = await notifier.addFromUserText('Rent');

      expect(id, SpendCategory.rent);
      expect(container.read(customSpendCategoriesProvider), isEmpty);
    });

    test('unusable text adds nothing and returns no id', () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);

      expect(await notifier.addFromUserText('###'), isNull);
      expect(container.read(customSpendCategoriesProvider), isEmpty);
    });

    test('the list stops growing at the cap', () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);

      for (var index = 0; index < CustomSpendCategory.maxPerUser; index++) {
        expect(await notifier.addFromUserText('category $index'), isNotNull);
      }

      expect(await notifier.addFromUserText('one too many'), isNull);
      expect(
        container.read(customSpendCategoriesProvider).length,
        CustomSpendCategory.maxPerUser,
      );
    });

    test('removing a category takes it out of the picker', () async {
      final container = makeContainer();
      final notifier = container.read(customSpendCategoriesProvider.notifier);
      await notifier.addFromUserText('Tax');

      await notifier.remove('custom:tax');

      expect(container.read(customSpendCategoriesProvider), isEmpty);
      expect(notifier.contains('custom:tax'), isFalse);
      // A transaction already filed under it still reads as a real word.
      expect(SpendCategory.label('custom:tax'), 'Tax');
    });

    test('the list survives a reload of the provider', () async {
      final container = makeContainer();
      await container
          .read(customSpendCategoriesProvider.notifier)
          .addFromUserText('Income Tax');

      // A second container reads the same persisted key, standing in for the
      // next app launch.
      final next = ProviderContainer();
      addTearDown(next.dispose);
      next.read(customSpendCategoriesProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        next.read(customSpendCategoriesProvider).single.label,
        'Income Tax',
      );
    });

    test('a corrupt stored list does not block categorising', () async {
      const storage = SecureStorageService();
      await storage.write(
        UserScopedStorageKeys.customSpendCategories('guest'),
        'not json at all',
      );

      final container = makeContainer();
      container.read(customSpendCategoriesProvider);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(customSpendCategoriesProvider), isEmpty);
      expect(
        await container
            .read(customSpendCategoriesProvider.notifier)
            .addFromUserText('Tax'),
        'custom:tax',
      );
    });
  });

  group('the picker order', () {
    test('built-ins come first, then the user list, with Other last', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(customSpendCategoriesProvider.notifier)
          .addFromUserText('Income tax');

      final order = container.read(spendCategoryPickerProvider);

      expect(order.first, SpendCategory.food);
      expect(order.last, SpendCategory.other);
      expect(order, contains('custom:income_tax'));
      expect(
        order.indexOf('custom:income_tax'),
        greaterThan(order.indexOf(SpendCategory.cash)),
      );
      expect(
        order.where((category) => category == SpendCategory.other).length,
        1,
        reason: 'Other must not appear twice',
      );
    });
  });

  group('storage wiring', () {
    test('the key is user scoped', () {
      expect(
        UserScopedStorageKeys.customSpendCategories('user-1'),
        isNot(UserScopedStorageKeys.customSpendCategories('user-2')),
      );
    });

    test('the list is backed up and cleared with the rest of the account', () {
      expect(
        UserScopedStorageKeys.durableNamespaces,
        contains('custom-spend-categories'),
      );
      expect(
        UserScopedStorageKeys.allForUser('user-1'),
        contains(UserScopedStorageKeys.customSpendCategories('user-1')),
      );
      expect(
        UserScopedStorageKeys.durableNamespaceForKey(
          'user-1',
          UserScopedStorageKeys.customSpendCategories('user-1'),
        ),
        'custom-spend-categories',
      );
    });
  });
}
