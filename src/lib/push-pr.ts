export function shouldOfferPushPr(params: {
  isStreaming: boolean;
  hasPr: boolean;
  branchAhead: boolean;
}): boolean {
  return !params.isStreaming && !params.hasPr && params.branchAhead;
}
