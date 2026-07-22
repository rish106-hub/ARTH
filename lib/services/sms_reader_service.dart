import 'package:another_telephony/telephony.dart';

/// A raw SMS reduced to the fields the parser needs.
typedef RawSms = ({String sender, String body, DateTime date});

/// Thin wrapper over `another_telephony` for reading the SMS inbox on Android.
/// Kept deliberately free of parsing/business logic so it stays easy to reason
/// about and the parser can be unit-tested without the platform channel.
class SmsReaderService {
  SmsReaderService({Telephony? telephony})
      : _telephony = telephony ?? Telephony.instance;

  final Telephony _telephony;

  /// Prompts for READ_SMS / RECEIVE_SMS. Returns true if granted.
  Future<bool> requestPermission() async {
    final granted = await _telephony.requestSmsPermissions;
    return granted ?? false;
  }

  /// Reads inbox SMS, newest first, optionally limited to messages on/after
  /// [since]. Returns lightweight [RawSms] records.
  Future<List<RawSms>> readInbox({DateTime? since}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    final result = <RawSms>[];
    for (final message in messages) {
      final body = message.body;
      final millis = message.date;
      if (body == null || body.isEmpty || millis == null) continue;
      final date = DateTime.fromMillisecondsSinceEpoch(millis);
      // Inbox is sorted DATE DESC, so the first out-of-window message means
      // every remaining one is older too.
      if (since != null && date.isBefore(since)) break;
      result.add((
        sender: message.address ?? 'unknown',
        body: body,
        date: date,
      ));
    }
    return result;
  }
}
