import 'package:backend/src/comments_repository.dart';
import 'package:test/test.dart';

void main() {
  late CommentsRepository repo;

  setUp(() => repo = CommentsRepository(':memory:'));
  tearDown(() => repo.close());

  group('CommentsRepository', () {
    test('stores a comment and reads it back as stored', () {
      final stored = repo.add(
        clientId: '1130488',
        userId: 'r14878',
        role: 'Checker',
        comments: 'Checked in core.',
      );

      expect(stored['client_id'], '1130488');
      expect(stored['user_id'], 'r14878');
      expect(stored['role'], 'Checker');
      expect(stored['comments'], 'Checked in core.');
      // The server's stamp, not the caller's — a client clock that is out
      // would order the thread wrongly for everyone else.
      expect(DateTime.parse(stored['created_at'] as String).isUtc, isTrue);
      expect(stored['id'], isNotNull);
    });

    test("a thread is one case's comments, in the order written", () {
      repo
        ..add(
          clientId: '1',
          userId: 'mk',
          role: 'Maker',
          comments: 'First',
        )
        ..add(
          clientId: '2',
          userId: 'mk',
          role: 'Maker',
          comments: 'Another case',
        )
        ..add(
          clientId: '1',
          userId: 'ck',
          role: 'Checker',
          comments: 'Second',
        );

      expect(
        [for (final row in repo.forClient('1')) row['comments']],
        ['First', 'Second'],
      );
    });

    test('the thread is not narrowed to whoever wrote it', () {
      // The point of it: the maker has to read what the checker wrote, or the
      // record collects two monologues.
      repo
        ..add(clientId: '1', userId: 'mk', role: 'Maker', comments: 'Raised')
        ..add(
          clientId: '1',
          userId: 'ck',
          role: 'Checker',
          comments: 'Cleared',
        );

      expect(repo.forClient('1'), hasLength(2));
    });

    test('a case nobody has commented on has an empty thread', () {
      expect(repo.forClient('nothing-here'), isEmpty);
      expect(repo.count(), 0);
    });
  });
}
