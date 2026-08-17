/// Rough token count for a prompt, used only to size a budget check before a
/// call is made. Deliberately crude: the provider's own usage figures are what
/// get recorded afterwards, so this only needs to be close enough to stop a call
/// that cannot fit inside the remaining budget from starting.
///
/// Lives in its own module, with no imports, so that provider clients can size a
/// budget check without pulling in the database or the environment config.
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}
