export default function DeviceListPanel({ devices }) {
  if (!devices || devices.length === 0) {
    return (
      <div className="text-zinc-400 text-sm">
        No devices registered.
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {devices.map((d) => (
        <div
          key={d.device_id}
          className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4"
        >
          <div className="flex justify-between">
            <div className="font-medium">{d.device_id}</div>
            <div className="text-xs text-zinc-400">{d.status}</div>
          </div>

          <div className="mt-2 text-xs text-zinc-500">
            OS: {d.os_family} · Trust: {d.trust_level}
          </div>
        </div>
      ))}
    </div>
  );
}