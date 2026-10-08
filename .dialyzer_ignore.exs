# Ecto.Multi stores an opaque MapSet; on OTP 28+ Dialyzer reports every
# Ecto.Multi pipeline as call_without_opaque.
# This is a false positive.
[
  {"lib/tannhauser_gate/accounts.ex", :call_without_opaque},
  {"lib/tannhauser_gate/forum.ex", :call_without_opaque}
]
