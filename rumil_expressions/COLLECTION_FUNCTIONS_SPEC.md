# Collection Functions Specification

## Context

Lambé (the query language built on Rumil) reimplements collection operations that should live upstream in rumil_expressions. Adding them here avoids dual implementation and makes them available to any rumil_expressions user.

This is additive — no existing API changes, just new functions in `builtinFunctions` and exported as standalone functions for direct use.

## Current state

`builtinFunctions` in `environment.dart` has:
- Math: `abs`, `ceil`, `floor`, `round`, `sqrt`, `min` (2-arg numeric), `max` (2-arg numeric)
- String: `length` (string only), `uppercase`, `lowercase`

## Changes

### 1. Expand existing functions

**`length`** — currently string-only. Add list and map support:
```dart
'length': (args) {
  final v = args[0];
  if (v is List) return v.length;
  if (v is Map) return v.length;
  if (v is String) return v.length;
  throw EvalException('length: expected list, map, or string, got ${v.runtimeType}');
},
```
Return type changes from `double` to `int` for all cases. This is technically breaking but the old `v.length.toDouble()` return was wrong — lengths are integers.

**`min` / `max`** — currently 2-arg numeric. Add 1-arg list overload:
```dart
'min': (args) {
  if (args.length == 1 && args[0] is List) return _collectionMin(args[0] as List<Object>);
  return math.min(_asNum(args[0], 'min'), _asNum(args[1], 'min'));
},
```
When called with one list argument, returns the minimum element. When called with two numeric arguments, behaves as before. Same for `max`.

### 2. New collection functions

All take a single argument. The argument must be a `List<Object>` unless noted.

| Function | Behavior | Returns | Error |
|----------|----------|---------|-------|
| `sum` | Sum all numeric elements | `num` (int if all int, double otherwise) | Throws if any element is not `num` |
| `avg` | Average of all numeric elements | `double` | Throws if empty or non-numeric |
| `count` | Number of elements | `int` | Same as `length` on list — alias for discoverability |
| `sort` | Sort elements naturally | `List<Object>` (new list) | Throws if elements are not mutually comparable |
| `reverse` | Reverse element order | `List<Object>` (new list) | |
| `unique` | Deduplicate elements (preserves first occurrence order) | `List<Object>` (new list) | |
| `flatten` | Flatten one level of nesting | `List<Object>` | Non-list elements pass through |
| `keys` | Map → key list, List → index list | `List<Object>` | Throws if not map or list |
| `values` | Map → value list, List → itself | `List<Object>` | Throws if not map or list |
| `first` | First element | `Object?` | Returns `null` if empty |
| `last` | Last element | `Object?` | Returns `null` if empty |

### 3. Implementation details

**`sum`:**
```dart
Object _collectionSum(Object arg) {
  final list = _asList(arg, 'sum');
  num total = 0;
  for (final item in list) {
    total += _asNum(item, 'sum');
  }
  return total;
}
```
Note: returns `int` when all elements are `int` (because `int + int = int` in Dart). Returns `double` when any element is `double`.

**`avg`:**
```dart
Object _collectionAvg(Object arg) {
  final list = _asList(arg, 'avg');
  if (list.isEmpty) throw EvalException('avg: empty list');
  return (_collectionSum(list) as num).toDouble() / list.length;
}
```
Always returns `double`.

**`sort`:**
```dart
Object _collectionSort(Object arg) {
  final list = List<Object>.of(_asList(arg, 'sort'));
  list.sort((a, b) => _compare(a, b));
  return list;
}

int _compare(Object a, Object b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return a.toString().compareTo(b.toString());
  throw EvalException('sort: cannot compare ${a.runtimeType} with ${b.runtimeType}');
}
```
Returns a new sorted list. Does not mutate the input. Throws on mixed types.

**`unique`:**
```dart
Object _collectionUnique(Object arg) {
  final list = _asList(arg, 'unique');
  final seen = <Object>{};
  return [for (final item in list) if (seen.add(item)) item];
}
```
Preserves first-occurrence order. Uses `Object.==` and `Object.hashCode`.

**`flatten`:**
```dart
Object _collectionFlatten(Object arg) {
  final list = _asList(arg, 'flatten');
  return [for (final item in list) if (item is List) ...item else item];
}
```
One level only. `[[1,2],[3]]` → `[1,2,3]`. `[1,[2,[3]]]` → `[1,2,[3]]`.

**`keys` / `values`:**
```dart
Object _collectionKeys(Object arg) {
  if (arg is Map<String, Object>) return arg.keys.toList();
  if (arg is List<Object>) return [for (var i = 0; i < arg.length; i++) i];
  throw EvalException('keys: expected map or list');
}
```

### 4. Exported API

In addition to adding these to `builtinFunctions`, export them as standalone functions for direct use by downstream packages (like Lambé):

```dart
/// Collection functions usable standalone or via [Environment.standard].
///
/// These operate on `Object` arguments (typically `List<Object>` or
/// `Map<String, Object>`) and return `Object`.
const collectionFunctions = <String, Object Function(List<Object>)>{
  'sum': ...,
  'avg': ...,
  'count': ...,
  'sort': ...,
  'reverse': ...,
  'unique': ...,
  'flatten': ...,
  'keys': ...,
  'values': ...,
  'first': ...,
  'last': ...,
};
```

And `Environment.standard()` merges both:
```dart
factory Environment.standard({...}) => Environment(
  variables: variables,
  functions: {...builtinFunctions, ...collectionFunctions, ...functions},
);
```

This keeps the existing `builtinFunctions` (math + string) separate from the new `collectionFunctions` for users who want only one set.

### 5. Helper extraction

The `_asNum` and `_asList` helpers are needed by both the existing evaluator and the new collection functions. They already exist in `evaluator.dart`. Move them (or their equivalents) to a shared location — either `environment.dart` or a new `helpers.dart` — so both the evaluator and the collection functions can use them without duplication.

```dart
/// Cast to num or throw.
num asNum(Object v, String ctx) {
  if (v is num) return v;
  throw EvalException('$ctx: expected number, got ${v.runtimeType}');
}

/// Cast to list or throw.
List<Object> asList(Object v, String ctx) {
  if (v is List<Object>) return v;
  throw EvalException('$ctx: expected list, got ${v.runtimeType}');
}
```

These could be exported as public utilities if other packages need them, or kept internal with `_` prefix if only used within rumil_expressions.

### 6. Tests

Add to `test/expression_test.dart` (or a new `test/collection_test.dart`):

**sum:**
- `sum([1, 2, 3])` → `6` (int)
- `sum([1.5, 2.5])` → `4.0` (double)
- `sum([])` → `0`
- `sum([1, "a"])` → throws

**avg:**
- `avg([2, 4, 6])` → `4.0`
- `avg([])` → throws

**min / max (list overload):**
- `min([3, 1, 2])` → `1`
- `max([3, 1, 2])` → `3`
- `min(["b", "a", "c"])` → `"a"`
- `min([])` → throws
- `min(2, 5)` → `2` (existing 2-arg behavior preserved)

**sort:**
- `sort([3, 1, 2])` → `[1, 2, 3]`
- `sort(["b", "a"])` → `["a", "b"]`
- `sort([])` → `[]`
- `sort([1, "a"])` → throws

**reverse:**
- `reverse([1, 2, 3])` → `[3, 2, 1]`

**unique:**
- `unique([1, 2, 1, 3, 2])` → `[1, 2, 3]`
- `unique([])` → `[]`

**flatten:**
- `flatten([[1, 2], [3]])` → `[1, 2, 3]`
- `flatten([1, [2, [3]]])` → `[1, 2, [3]]` (one level only)
- `flatten([])` → `[]`

**keys / values:**
- `keys({"a": 1, "b": 2})` → `["a", "b"]`
- `values({"a": 1, "b": 2})` → `[1, 2]`
- `keys([10, 20])` → `[0, 1]`

**length (expanded):**
- `length([1, 2, 3])` → `3`
- `length({"a": 1})` → `1`
- `length("hello")` → `5`
- `length(42)` → throws

**first / last:**
- `first([10, 20])` → `10`
- `last([10, 20])` → `20`
- `first([])` → throws or returns null (decide: Lambé returns null, rumil_expressions may prefer throwing for consistency with avg/min/max)

### 7. Version note

These additions are non-breaking (new functions only, existing behavior preserved except `length` returning `int` instead of `double`). However, since rumil 0.2.0 is already planned for the `fail→failure` rename, these should land in the same release. The rumil_expressions version bump would be 0.2.0 to match the rumil dependency change.

### 8. After this lands

Lambé will:
1. Update dependency to `rumil_expressions: ^0.2.0`
2. Import `collectionFunctions` (or the standalone functions)
3. Replace `_sum`, `_avg`, `_sort`, etc. in `evaluator.dart` with calls to the shared implementations
4. Remove the duplicated helper functions
