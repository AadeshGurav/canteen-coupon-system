/// A shared "argument not supplied" marker for partial-update APIs, so a
/// caller can distinguish "leave this field alone" (omit / pass [kUnset]) from
/// "set this field to null" (pass null). Using one shared instance means
/// `identical(value, kUnset)` works across library boundaries.
const Object kUnset = _Unset();

class _Unset {
  const _Unset();
}
