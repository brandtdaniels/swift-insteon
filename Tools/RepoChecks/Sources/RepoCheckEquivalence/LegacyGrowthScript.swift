import Foundation

/// The four shell blocks of the CI step that compared each allow-list with its base, as they
/// were written there, run one after another, so the Swift check can be compared with them.
/// Deleted with the Python.
enum LegacyGrowthScript {
  static let text = ##"""
    #!/bin/bash
    export LC_ALL=C
    export BASE_REF="${1:-main}"
    status=0
    (
      list=Scripts/check-cli-thin-allowlist.txt
      if ! git cat-file -e "origin/${BASE_REF}:${list}" 2>/dev/null; then
        echo "The base branch has no allow-list yet, so there's nothing to compare."
        exit 0
      fi
      added=$(git diff --no-color --unified=0 "origin/${BASE_REF}" -- "$list" | grep -E '^\+[^+#]' || true)
      if [ -n "$added" ]; then
        echo "These lines were added to $list, which may only lose lines:"
        echo "$added"
        echo "Move the code into the libraries instead of allowing it."
        exit 1
      fi
      echo "The allow-list didn't grow."
    ) || status=1
    (
      list=Scripts/check-concurrency-allowlist.txt
      if ! git cat-file -e "origin/${BASE_REF}:${list}" 2>/dev/null; then
        echo "The base branch has no allow-list yet, so there's nothing to compare."
        exit 0
      fi
      entries() { grep -v -e '^#' -e '^$' | cut -f1-3 | sort; }
      added=$(comm -13 <(git show "origin/${BASE_REF}:${list}" | entries) <(entries < "$list"))
      if [ -n "$added" ]; then
        echo "These entries were added to $list, which may only lose entries:"
        echo "$added"
        echo "Keep the work structured and the clock injected instead of allowing it."
        exit 1
      fi
      echo "The allow-list didn't grow."
    ) || status=1
    (
      list=Scripts/check-credentials-allowlist.txt
      if ! git cat-file -e "origin/${BASE_REF}:${list}" 2>/dev/null; then
        echo "The base branch has no allow-list yet, so there's nothing to compare."
        exit 0
      fi
      entries() { grep -v -e '^#' -e '^$' | cut -f1-2 | sort; }
      added=$(comm -13 <(git show "origin/${BASE_REF}:${list}" | entries) <(entries < "$list"))
      if [ -n "$added" ]; then
        echo "These entries were added to $list, which may only lose entries:"
        echo "$added"
        echo "Leave the credential out of the string instead of allowing it."
        exit 1
      fi
      echo "The allow-list didn't grow."
    ) || status=1
    (
      list=Scripts/check-device-neutral-allowlist.txt
      if ! git cat-file -e "origin/${BASE_REF}:${list}" 2>/dev/null; then
        echo "The base branch has no allow-list yet, so there's nothing to compare."
        exit 0
      fi
      entries() { grep -v -e '^#' -e '^$' | cut -f1-2 | sort; }
      added=$(comm -13 <(git show "origin/${BASE_REF}:${list}" | entries) <(entries < "$list"))
      if [ -n "$added" ]; then
        echo "These entries were added to $list, which may only lose entries:"
        echo "$added"
        echo "Take the name from the catalog, or use an invented one, instead of allowing it."
        exit 1
      fi
      echo "The allow-list didn't grow."
    ) || status=1
    exit $status

    """##
}
