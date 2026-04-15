export default function FreezeEvidencePanel({ freezeEvidence }) {
  if (!freezeEvidence) {
    return (
      <div className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4 text-zinc-400">
        No freeze evidence available.
      </div>
    );
  }

  const Row = ({ label, value }) => (
    <div className="flex items-center justify-between text-xs">
      <span className="text-zinc-500">{label}</span>
      <span className="text-zinc-200 break-all text-right">{value || "—"}</span>
    </div>
  );

  return (
    <div className="rounded-2xl border border-emerald-500/20 bg-emerald-500/5 p-4">
      <div className="text-sm font-medium text-emerald-300">
        Freeze evidence bundle
      </div>

      <div className="mt-3 space-y-2">
        <Row label="Freeze root" value={freezeEvidence.freezeRoot} />
        <Row label="Manifest" value={freezeEvidence.manifest} />
        <Row label="sha256sums" value={freezeEvidence.sha256sums} />
        <Row label="Full green stdout" value={freezeEvidence.fullGreenStdout} />
        <Row label="Full green stderr" value={freezeEvidence.fullGreenStderr} />
        <Row label="Binding stdout" value={freezeEvidence.bindingStdout} />
        <Row label="Binding stderr" value={freezeEvidence.bindingStderr} />
        <Row label="Tier-0 receipt" value={freezeEvidence.tier0Receipt} />
      </div>
    </div>
  );
}
