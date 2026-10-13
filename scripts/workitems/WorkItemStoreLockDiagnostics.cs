// Isolated source proposal. No compilation or runtime evidence accompanies this file.
using System;
using System.IO;
using System.IO.Pipes;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Xml;
using Microsoft.Win32.SafeHandles;

namespace AgentOrg.LockDiagnosticsV1 {
    [DataContract] public sealed class OriginalMetadata {
        [DataMember] public string lockId;
        [DataMember] public string storePath;
        [DataMember] public int processId;
        [DataMember] public string processStartedAtUtc;
        [DataMember] public string ownerSid, ownerName, host, acquiredAtUtc;
    }
    [DataContract] public sealed class Request {
        [DataMember] public int version;
        [DataMember] public string command, requestId, storePath, lockPath, lockId;
        [DataMember] public int processId;
        [DataMember] public long processStartFileTime;
        [DataMember] public string originalMetadataHash, objectIdentity;
        [DataMember] public string ownerSid, ownerName, host, acquiredAtUtc, processStartedAtUtc;
    }
    [DataContract] public sealed class Owner {
        [DataMember] public string ownerSid, ownerName, host, acquiredAtUtc, processStartedAtUtc;
        [DataMember] public int processId;
        // Decimal string preserves FILETIME through the JavaScript transport (>2^53).
        [DataMember] public string processStartFileTime;
    }
    [DataContract] public sealed class Response {
        [DataMember] public int version;
        [DataMember] public string state, reason, requestId, storePath, lockPath, lockId;
        [DataMember] public int processId, attemptOrdinal;
        [DataMember] public long processStartFileTime;
        [DataMember] public string originalMetadataHash, objectIdentity, queryStartedAtUtc, queryCompletedAtUtc;
        [DataMember] public Owner owner;
    }
    public sealed class Observation {
        public string state = "unknown", reason = "routeUnavailable", currentOwnership = "unconfirmed";
        public string bindingStatus = "unconfirmed", sourceReference = "producerOriginalHandle/v1", completeness = "unknown";
        public string senderBinding, acquisitionBinding, metadataBinding, objectBinding;
        public string queryStartedAtUtc, queryCompletedAtUtc, receivedAtUtc, diagnosticCompletedAtUtc;
        public string requestId, lockId, originalMetadataHash, objectIdentity;
        public int? attemptOrdinal;
        public Owner owner;
    }
    // All scalar data are copied before publication; no PSObject access on the worker.
    public sealed class Acquisition {
        internal readonly string Store, LockPath, LockId, Hash, Sid, Name, Host, Acquired, ProcessUtc;
        internal readonly int Pid, Attempt;
        internal readonly long Start;
        public Acquisition(string store, string path, string id, int attempt, string hash,
            string sid, string name, int pid, long start, string processUtc, string host, string acquired) {
            Store = Path.GetFullPath(store); LockPath = Path.GetFullPath(path);
            Guid parsed;
            if (!Guid.TryParseExact(id, "D", out parsed) || parsed.ToString("D") != id || attempt < 1 || pid < 1 || start <= 0 || !Wire.Hex(hash, 64))
                throw new ArgumentException("invalid acquisition");
            if (LockPath != Store + ".lock" || ProcessTime(processUtc) != start) throw new ArgumentException("acquisition path/generation");
            // Validate SID before constructing a security descriptor; no string injection.
            Sid = new SecurityIdentifier(sid).Value;
            LockId = id; Attempt = attempt; Hash = hash; Name = name; Pid = pid;
            Start = start; ProcessUtc = processUtc; Host = host; Acquired = acquired;
            Wire.Utc(acquired);
        }
        internal static long ProcessTime(string utc) { return Wire.Utc(utc).ToFileTimeUtc(); }
    }
    public sealed class Entry {
        internal readonly Registry Registry;
        internal readonly object Context, Token;
        internal readonly FileStream Original;
        internal readonly SafeFileHandle Handle; // borrowed, never disposed by diagnostics
        internal readonly Acquisition Data;
        internal readonly PipeLifetime Pipe;
        internal bool Active;
        internal Thread Worker;
        internal string StopStatus = "notStarted";
        internal Entry(Registry registry, object context, object token, FileStream stream, SafeFileHandle handle, Acquisition data, PipeLifetime pipe) {
            Registry = registry; Context = context; Token = token; Original = stream; Handle = handle; Data = data; Pipe = pipe;
        }
    }
    public sealed class Registry : IDisposable {
        public readonly object Gate = new object();
        readonly HashSet<Entry> entries = new HashSet<Entry>();
        bool disposed;
        void RequireGate() { if (!Monitor.IsEntered(Gate)) throw new InvalidOperationException("shared gate required"); }
        // Caller publishes the PS registry in the same critical section. Endpoint is created
        // synchronously here, after Flush, but the worker starts only after publication.
        public Entry Register(object context, object token, FileStream original, Acquisition data) {
            RequireGate();
            if (disposed || context == null || token == null || original == null) throw new InvalidOperationException("registry unavailable");
            long position = original.Position;
            SafeFileHandle handle;
            try { handle = original.SafeFileHandle; } finally { original.Position = position; }
            if (handle.IsInvalid || handle.IsClosed) throw new IOException("original handle unavailable");
            var pipe = new PipeLifetime(Native.Server(data));
            try {
                var entry = new Entry(this, context, token, original, handle, data, pipe);
                entries.Add(entry); entry.Active = true;
                return entry;
            } catch { pipe.CancelAndDispose(); throw; }
        }
        public void Start(Entry entry, object context, object token) {
            lock (Gate) {
                if (!Matches(entry, context, token)) throw new InvalidOperationException("entry not published");
                if (entry.Worker != null) throw new InvalidOperationException("worker already started");
                entry.Worker = new Thread(delegate() { Serve(entry); });
                entry.Worker.IsBackground = true;
                entry.Worker.Name = "WorkItem original lock diagnostic";
                entry.Worker.Start();
            }
        }
        bool Matches(Entry e, object context, object token) {
            return e != null && ReferenceEquals(e.Registry, this) && entries.Contains(e) && e.Active &&
                ReferenceEquals(e.Context, context) && ReferenceEquals(e.Token, token);
        }
        public void Retire(Entry entry, object context, object token) {
            RequireGate();
            if (entry == null) return;
            if (!ReferenceEquals(entry.Registry, this) || !ReferenceEquals(entry.Context, context) || !ReferenceEquals(entry.Token, token))
                throw new InvalidOperationException("retire binding mismatch");
            entry.Active = false; entries.Remove(entry);
        }
        void RetireWorker(Entry entry) { lock (Gate) { entry.Active = false; entries.Remove(entry); } }
        public string Stop(Entry entry) {
            if (entry == null) return "unavailable";
            if (Monitor.IsEntered(Gate)) throw new InvalidOperationException("stop outside shared gate");
            entry.Pipe.CancelAndDispose();
            Thread worker = entry.Worker;
            bool terminal = worker == null || !worker.IsAlive || (worker != Thread.CurrentThread && worker.Join(500));
            // Worker termination alone does not confirm a concurrent or failed cleanup.
            entry.StopStatus = terminal && entry.Pipe.IoTerminal && entry.Pipe.CleanupConfirmed ? "stopped" : "stopUnconfirmed";
            return entry.StopStatus; // no Abort/kill; worker owns its late completion
        }
        Response Observe(Entry e, Request r) {
            if (!Monitor.TryEnter(Gate, 100)) return Wire.Unknown(r, "busy");
            try {
                if (disposed || !Matches(e, e.Context, e.Token) || e.Pipe.Stopped) return Wire.Unknown(r, "stopping");
                Acquisition d = e.Data;
                if (!Wire.RequestMatches(r, d)) return Wire.Unknown(r, "acquisitionMismatch");
                string begin = DateTime.UtcNow.ToString("o");
                string identity;
                try {
                    if (e.Handle.IsClosed || e.Handle.IsInvalid) return Wire.Unknown(r, "queryFailed");
                    Native.RequireRouteFile(e.Handle);
                    identity = Native.Identity(e.Handle);
                } catch { return Wire.Unknown(r, "queryFailed"); }
                if (identity != r.objectIdentity) return Wire.Unknown(r, "objectMismatch");
                string end = DateTime.UtcNow.ToString("o");
                return new Response { version = 1, state = "observed", requestId = r.requestId,
                    storePath = d.Store, lockPath = d.LockPath, lockId = d.LockId,
                    processId = d.Pid, processStartFileTime = d.Start, attemptOrdinal = d.Attempt,
                    originalMetadataHash = d.Hash, objectIdentity = identity,
                    queryStartedAtUtc = begin, queryCompletedAtUtc = end,
                    owner = new Owner { ownerSid = d.Sid, ownerName = d.Name, host = d.Host,
                        acquiredAtUtc = d.Acquired, processId = d.Pid, processStartFileTime = d.Start.ToString(CultureInfo.InvariantCulture), processStartedAtUtc = d.ProcessUtc } };
            } finally { Monitor.Exit(Gate); }
        }
        void Serve(Entry entry) {
            var server = (NamedPipeServerStream)entry.Pipe.Stream;
            try {
                while (!entry.Pipe.Stopped) {
                    // The server waits without a frame deadline; Stop cancels/disposes and
                    // this worker still observes terminal completion before releasing references.
                    Wire.Complete(server.WaitForConnectionAsync(), entry.Pipe, null);
                    var budget = Stopwatch.StartNew();
                    Request request = Wire.Decode<Request>(Wire.ReadFrame(entry.Pipe, 16384, budget));
                    if (!Wire.ValidRequest(request)) throw new IOException("invalid frame/request");
                    Response response = Observe(entry, request); // only original query is under Gate
                    Wire.WriteFrame(entry.Pipe, Wire.Encode(response), 32768, budget);
                    server.Disconnect(); // all started operations completed normally
                }
            } catch { /* Any malformed frame, timeout or I/O failure retires this endpoint. */ }
            finally { RetireWorker(entry); entry.Pipe.CancelAndDispose(); }
        }
        public void Dispose() {
            Entry[] retiring;
            lock (Gate) {
                disposed = true; retiring = new Entry[entries.Count]; entries.CopyTo(retiring);
                foreach (Entry e in retiring) e.Active = false;
                entries.Clear();
            }
            foreach (Entry e in retiring) Stop(e);
        }
    }
    internal sealed class PipeLifetime {
        internal readonly PipeStream Stream;
        int stopRequested, cleanupState, pendingIo;
        // cleanupState: 0 not begun, 1 in progress, 2 confirmed, 3 failed.
        // A concurrent caller observes state; it never retries a possibly reused handle.
        internal bool Stopped { get { return Volatile.Read(ref stopRequested) != 0; } }
        internal bool CleanupConfirmed { get { return Volatile.Read(ref cleanupState) == 2; } }
        internal bool IoTerminal { get { return Volatile.Read(ref pendingIo) == 0; } }
        internal void TrackIo() { Interlocked.Increment(ref pendingIo); }
        internal void CompleteIo() { Interlocked.Decrement(ref pendingIo); }
        internal PipeLifetime(PipeStream stream) { Stream = stream; }
        internal bool CancelAndDispose() {
            Interlocked.Exchange(ref stopRequested, 1);
            if (Interlocked.CompareExchange(ref cleanupState, 1, 0) != 0) return CleanupConfirmed;
            bool cancelAccepted = false, disposed = false;
            try {
                // ERROR_NOT_FOUND means no matching cancellation request, not terminal I/O.
                cancelAccepted = Native.CancelIoEx(Stream.SafePipeHandle, IntPtr.Zero);
                if (!cancelAccepted) cancelAccepted = Marshal.GetLastWin32Error() == 1168;
            } catch { cancelAccepted = false; }
            // Always attempt wrapper cleanup once, even when cancellation failed.
            try { Stream.Dispose(); disposed = true; } catch { disposed = false; }
            Volatile.Write(ref cleanupState, cancelAccepted && disposed ? 2 : 3);
            return CleanupConfirmed;
        }
    }
    internal static class Wire {
        internal static bool Hex(string s, int n) {
            if (s == null || s.Length != n) return false;
            foreach (char c in s) if (!(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f')) return false;
            return true;
        }
        internal static DateTime Utc(string s) {
            // Handle producer UTC-Z explicitly, regardless of DateTimeOffset Z behavior.
            DateTime utc;
            if (s != null && s.EndsWith("Z", StringComparison.Ordinal) &&
                DateTime.TryParseExact(s, "o", CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out utc) &&
                utc.Kind == DateTimeKind.Utc && utc.ToString("o", CultureInfo.InvariantCulture) == s)
                return utc;
            DateTimeOffset v;
            if (DateTimeOffset.TryParseExact(s, "o", CultureInfo.InvariantCulture, DateTimeStyles.None, out v) &&
                v.Offset == TimeSpan.Zero && v.ToString("o", CultureInfo.InvariantCulture) == s)
                return v.UtcDateTime;
            throw new IOException("invalid UTC");
        }
        internal static string Hash(byte[] b) { using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(b)).Replace("-", "").ToLowerInvariant(); }
        internal static byte[] Encode<T>(T value) {
            using (var stream = new MemoryStream()) { new DataContractJsonSerializer(typeof(T)).WriteObject(stream, value); return stream.ToArray(); }
        }
        internal static T Decode<T>(byte[] b) {
            new UTF8Encoding(false, true).GetString(b); // reject invalid UTF-8 before JSON decoding
            var quotas = new XmlDictionaryReaderQuotas {
                MaxDepth = 16, MaxStringContentLength = 65536, MaxArrayLength = 65536,
                MaxBytesPerRead = 4096, MaxNameTableCharCount = 4096
            };
            using (var reader = JsonReaderWriterFactory.CreateJsonReader(b, 0, b.Length, new UTF8Encoding(false, true), quotas, null))
                return (T)new DataContractJsonSerializer(typeof(T)).ReadObject(reader);
        }
        internal static bool ValidRequest(Request r) {
            Guid id, lockId;
            return r != null && r.version == 1 && r.command == "Observe" && Guid.TryParseExact(r.requestId, "D", out id) &&
                Guid.TryParseExact(r.lockId, "D", out lockId) && lockId.ToString("D") == r.lockId && r.processId > 0 && r.processStartFileTime > 0 &&
                !String.IsNullOrEmpty(r.storePath) && r.lockPath == r.storePath + ".lock" && Hex(r.originalMetadataHash, 64) &&
                r.objectIdentity != null && r.objectIdentity.Length == 49 && r.objectIdentity[16] == ':' &&
                Hex(r.objectIdentity.Substring(0, 16), 16) && Hex(r.objectIdentity.Substring(17), 32);
        }
        internal static bool RequestMatches(Request r, Acquisition d) {
            return ValidRequest(r) && r.storePath == d.Store && r.lockPath == d.LockPath && r.lockId == d.LockId &&
                r.processId == d.Pid && r.processStartFileTime == d.Start && r.originalMetadataHash == d.Hash &&
                r.ownerSid == d.Sid && r.ownerName == d.Name && r.host == d.Host && r.acquiredAtUtc == d.Acquired && r.processStartedAtUtc == d.ProcessUtc;
        }
        internal static Response Unknown(Request r, string reason) { return new Response { version = 1, state = "unknown", requestId = r.requestId, reason = reason }; }
        internal static void Complete(Task task, PipeLifetime pipe, Stopwatch budget) {
            pipe.TrackIo();
            try {
                bool timedOut = false;
                try {
                    if (budget != null) {
                        int left = Math.Max(0, 500 - (int)budget.ElapsedMilliseconds);
                        timedOut = Task.WhenAny(task, Task.Delay(left)).GetAwaiter().GetResult() != task;
                        if (timedOut) pipe.CancelAndDispose();
                    }
                    // Retain task/buffers and observe success/fault/cancellation to terminal completion.
                    // This may outlive budgets; no native timing guarantee is made.
                    task.GetAwaiter().GetResult();
                } catch { if (timedOut) throw new IOException("transportTimeout"); throw; }
                if (timedOut || pipe.Stopped || (budget != null && budget.ElapsedMilliseconds > 500)) {
                    pipe.CancelAndDispose(); throw new IOException("transportTimeout");
                }
            } finally {
                // Even a budget/wait failure must not release a nonterminal operation.
                try { task.GetAwaiter().GetResult(); } catch { /* Main path retains its failure. */ }
                finally { pipe.CompleteIo(); }
            }
        }
        static void ExactRead(PipeLifetime p, byte[] bytes, Stopwatch budget) {
            int offset = 0;
            while (offset < bytes.Length) {
                Task<int> task = p.Stream.ReadAsync(bytes, offset, bytes.Length - offset);
                Complete(task, p, budget);
                int count = task.GetAwaiter().GetResult();
                if (count <= 0) throw new EndOfStreamException();
                offset += count;
            }
        }
        internal static byte[] ReadFrame(PipeLifetime p, int limit, Stopwatch budget) {
            byte[] header = new byte[4]; ExactRead(p, header, budget);
            uint length = (uint)(header[0] | header[1] << 8 | header[2] << 16 | header[3] << 24);
            if (length == 0 || length > limit) throw new IOException("frame length");
            byte[] body = new byte[(int)length]; ExactRead(p, body, budget); return body;
        }
        internal static void WriteFrame(PipeLifetime p, byte[] body, int limit, Stopwatch budget) {
            if (body.Length == 0 || body.Length > limit) throw new IOException("frame length");
            byte[] header = { (byte)body.Length, (byte)(body.Length >> 8), (byte)(body.Length >> 16), (byte)(body.Length >> 24) };
            Complete(p.Stream.WriteAsync(header, 0, 4), p, budget);
            Complete(p.Stream.WriteAsync(body, 0, body.Length), p, budget);
        }
    }
    internal static class Native {
        [StructLayout(LayoutKind.Sequential)] internal struct FileIdInfo {
            internal ulong Volume;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)] internal byte[] Id;
        }
        [StructLayout(LayoutKind.Sequential)] struct StandardInfo {
            internal long AllocationSize, EndOfFile;
            internal uint NumberOfLinks;
            [MarshalAs(UnmanagedType.U1)] internal bool DeletePending;
            [MarshalAs(UnmanagedType.U1)] internal bool Directory;
        }
        [StructLayout(LayoutKind.Sequential)] struct AttributeTagInfo { internal uint Attributes, ReparseTag; }
        [StructLayout(LayoutKind.Sequential)] struct SecurityAttributes { internal int Length; internal IntPtr Descriptor; [MarshalAs(UnmanagedType.Bool)] internal bool Inherit; }
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int kind, out FileIdInfo info, uint size);
        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetFileIdentity(SafeHandle handle, int kind, out FileIdInfo info, uint size);
        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetStandard(SafeHandle handle, int kind, out StandardInfo info, uint size);
        [DllImport("kernel32.dll", EntryPoint = "GetFileInformationByHandleEx", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetAttributes(SafeHandle handle, int kind, out AttributeTagInfo info, uint size);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool CancelIoEx(SafePipeHandle handle, IntPtr overlapped);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern SafePipeHandle CreateNamedPipeW(string name, uint open, uint mode, uint instances, uint output, uint input, uint timeout, ref SecurityAttributes attributes);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revision, out IntPtr descriptor, out uint size);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr value);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint pid);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern SafeProcessHandle OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetProcessTimes(SafeProcessHandle process, out long creation, out long exit, out long kernel, out long user);
        internal static string Identity(SafeHandle handle) {
            FileIdInfo id;
            if (!GetFileIdentity(handle, 18, out id, (uint)Marshal.SizeOf(typeof(FileIdInfo)))) throw new IOException("FILE_ID_INFO unavailable");
            return id.Volume.ToString("x16") + ":" + BitConverter.ToString(id.Id).Replace("-", "").ToLowerInvariant();
        }
        internal static string Identity(SafeFileHandle handle) {
            FileIdInfo id;
            if (!GetFileInformationByHandleEx(handle, 18, out id, (uint)Marshal.SizeOf(typeof(FileIdInfo)))) throw new IOException("FILE_ID_INFO unavailable");
            return id.Volume.ToString("x16") + ":" + BitConverter.ToString(id.Id).Replace("-", "").ToLowerInvariant();
        }
        internal static void RequireRouteFile(SafeHandle handle) {
            StandardInfo info; AttributeTagInfo attributes;
            if (!GetStandard(handle, 1, out info, (uint)Marshal.SizeOf(typeof(StandardInfo))) || info.Directory || info.NumberOfLinks != 1 ||
                !GetAttributes(handle, 9, out attributes, (uint)Marshal.SizeOf(typeof(AttributeTagInfo))) || (attributes.Attributes & 0x410) != 0)
                throw new IOException("ambiguous route object");
            // DeletePending is not a liveness assertion: the exact registered DeleteOnClose
            // acquisition is compared later. This read must still close before pipe I/O.
        }
        internal static string PipeName(int pid, long start, string lockId, string store) {
            return "agent-org-lockdiag-v1-" + pid.ToString(CultureInfo.InvariantCulture) + "-" + start.ToString("x16") + "-" + lockId + "-" + Wire.Hash(new UTF8Encoding(false, true).GetBytes(Path.GetFullPath(store).ToUpperInvariant()));
        }
        internal static NamedPipeServerStream Server(Acquisition d) {
            IntPtr descriptor = IntPtr.Zero; SafePipeHandle handle = null;
            try {
                uint size;
                if (!ConvertStringSecurityDescriptorToSecurityDescriptorW("D:P(A;;GA;;;SY)(A;;GA;;;" + d.Sid + ")", 1, out descriptor, out size)) throw new IOException("pipe DACL unavailable");
                var attrs = new SecurityAttributes { Length = Marshal.SizeOf(typeof(SecurityAttributes)), Descriptor = descriptor, Inherit = false };
                handle = CreateNamedPipeW(@"\\.\pipe\" + PipeName(d.Pid, d.Start, d.LockId, d.Store), 0x40080003, 0x8, 1, 32772, 16388, 0, ref attrs);
                if (handle.IsInvalid) throw new IOException("endpointUnavailable");
                var stream = new NamedPipeServerStream(PipeDirection.InOut, true, false, handle);
                handle = null; // exactly one owner after constructor transfer
                return stream;
            } finally { if (handle != null) handle.Dispose(); if (descriptor != IntPtr.Zero) LocalFree(descriptor); }
        }
    }
    public static class Client {
        // Original byte read handle has explicit terminal CloseHandle evidence.
        sealed class ReadHandle : SafeHandle {
            internal bool ClosedSuccessfully;
            public ReadHandle() : base(new IntPtr(-1), true) { }
            public override bool IsInvalid { get { return handle == IntPtr.Zero || handle == new IntPtr(-1); } }
            protected override bool ReleaseHandle() {
                try { ClosedSuccessfully = CloseHandle(handle); return ClosedSuccessfully; }
                catch { ClosedSuccessfully = false; return false; } // no retry on a reused raw value
            }
        }
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern ReadHandle OpenRead(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool ReadFile(ReadHandle handle, [Out] byte[] buffer, uint count, out uint read, IntPtr overlapped);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool SetFilePointerEx(ReadHandle handle, long distance, out long position, uint method);
        static byte[] Bytes(ReadHandle handle) {
            long pos;
            if (!SetFilePointerEx(handle, 0, out pos, 0) || pos != 0) throw new IOException("route seek");
            using (var memory = new MemoryStream()) {
                byte[] buffer = new byte[4096];
                while (true) {
                    uint count, ask = (uint)Math.Min(4096, 65537 - memory.Length);
                    if (!ReadFile(handle, buffer, ask, out count, IntPtr.Zero) || count > ask) throw new IOException("route read");
                    if (count == 0) break;
                    memory.Write(buffer, 0, (int)count);
                    if (memory.Length > 65536) throw new IOException("route byte limit");
                }
                if (memory.Length == 0) throw new IOException("empty route");
                return memory.ToArray();
            }
        }
        static void SafePath(string path) {
            for (string p = path; !String.IsNullOrEmpty(p); p = Path.GetDirectoryName(p)) {
                if ((File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0) throw new IOException("unsafe path");
            }
            if ((File.GetAttributes(path) & FileAttributes.Directory) != 0) throw new IOException("not a file");
        }
        static Request Route(string store) {
            string path = store + ".lock"; SafePath(path);
            ReadHandle handle = null; byte[] bytes; string identity;
            try {
                // READ/READ|WRITE|DELETE, OPEN_EXISTING; no DELETE or inherited handle.
                handle = OpenRead(path, 0x80000000, 7, IntPtr.Zero, 3, 0x00200080, IntPtr.Zero);
                if (handle.IsInvalid) throw new IOException("routeUnavailable");
                Native.RequireRouteFile(handle);
                identity = Native.Identity(handle); bytes = Bytes(handle);
                byte[] second = Bytes(handle);
                if (Wire.Hash(bytes) != Wire.Hash(second) || identity != Native.Identity(handle)) throw new IOException("route changed");
                SafePath(path);
                // A separate control read binds only this open's path point, never continuity.
                ReadHandle control = OpenRead(path, 0x80000000, 7, IntPtr.Zero, 3, 0x00200080, IntPtr.Zero);
                bool controlValid = !control.IsInvalid;
                try { if (control.IsInvalid || Native.Identity(control) != identity) throw new IOException("path changed"); Native.RequireRouteFile(control); }
                finally { control.Dispose(); if (controlValid && !control.ClosedSuccessfully) throw new IOException("route closing unconfirmed"); }
            } finally {
                if (handle != null) { bool valid = !handle.IsInvalid; handle.Dispose(); if (valid && !handle.ClosedSuccessfully) throw new IOException("route closing unconfirmed"); }
            }
            OriginalMetadata metadata = Wire.Decode<OriginalMetadata>(bytes);
            if (metadata == null || metadata.storePath != store) throw new IOException("route store mismatch");
            var request = new Request { version = 1, command = "Observe", requestId = Guid.NewGuid().ToString("D"),
                storePath = store, lockPath = path, lockId = metadata.lockId, processId = metadata.processId,
                processStartFileTime = Acquisition.ProcessTime(metadata.processStartedAtUtc), originalMetadataHash = Wire.Hash(bytes), objectIdentity = identity,
                ownerSid = metadata.ownerSid, ownerName = metadata.ownerName, host = metadata.host, acquiredAtUtc = metadata.acquiredAtUtc, processStartedAtUtc = metadata.processStartedAtUtc };
            if (!Wire.ValidRequest(request)) throw new IOException("route fields");
            return request;
        }
        static void ConfirmSender(PipeLifetime pipe, SafeProcessHandle process, Request request) {
            uint pid; long start, exit, kernel, user;
            if (!Native.GetNamedPipeServerProcessId(pipe.Stream.SafePipeHandle, out pid) || pid != request.processId ||
                process.IsInvalid || !Native.GetProcessTimes(process, out start, out exit, out kernel, out user) || start != request.processStartFileTime)
                throw new IOException("senderMismatch");
        }
        public static Observation Observe(string storePath) {
            var result = new Observation(); PipeLifetime pipe = null; SafeProcessHandle process = null;
            try {
                string store = Path.GetFullPath(storePath);
                Request request = Route(store); // all private original read handles closed before IPC
                result.reason = "endpointUnavailable";
                var stream = new NamedPipeClientStream(".", Native.PipeName(request.processId, request.processStartFileTime, request.lockId, store), PipeDirection.InOut, PipeOptions.Asynchronous);
                pipe = new PipeLifetime(stream);
                // Connect timeout faults terminally; stop/cleanup still observe its completion.
                Wire.Complete(stream.ConnectAsync(250), pipe, null);
                var budget = Stopwatch.StartNew();
                uint sender;
                if (!Native.GetNamedPipeServerProcessId(stream.SafePipeHandle, out sender) || sender != request.processId) throw new IOException("senderMismatch");
                process = Native.OpenProcess(0x1000, false, sender);
                ConfirmSender(pipe, process, request);
                Wire.WriteFrame(pipe, Wire.Encode(request), 16384, budget);
                byte[] responseBytes = Wire.ReadFrame(pipe, 32768, budget);
                string received = DateTime.UtcNow.ToString("o");
                Response response = Wire.Decode<Response>(responseBytes);
                ConfirmSender(pipe, process, request); // same held process and pipe after response
                if (response == null || response.version != 1 || response.requestId != request.requestId) throw new IOException("response mismatch");
                if (response.state != "observed") { result.reason = AllowedReason(response.reason); return result; }
                if (response.storePath != request.storePath || response.lockPath != request.lockPath || response.lockId != request.lockId ||
                    response.processId != request.processId || response.processStartFileTime != request.processStartFileTime || response.attemptOrdinal < 1)
                    throw new IOException("acquisitionMismatch");
                if (response.originalMetadataHash != request.originalMetadataHash) throw new IOException("metadataMismatch");
                if (response.objectIdentity != request.objectIdentity) throw new IOException("objectMismatch");
                DateTime begin = Wire.Utc(response.queryStartedAtUtc), end = Wire.Utc(response.queryCompletedAtUtc);
                if (end < begin || end > Wire.Utc(received) || response.owner == null || response.owner.processId != request.processId ||
                    response.owner.processStartFileTime != request.processStartFileTime.ToString(CultureInfo.InvariantCulture) || Acquisition.ProcessTime(response.owner.processStartedAtUtc) != request.processStartFileTime ||
                    response.owner.ownerSid != request.ownerSid || response.owner.ownerName != request.ownerName || response.owner.host != request.host ||
                    response.owner.acquiredAtUtc != request.acquiredAtUtc || response.owner.processStartedAtUtc != request.processStartedAtUtc ||
                    String.IsNullOrEmpty(response.owner.ownerName) || String.IsNullOrEmpty(response.owner.host)) throw new IOException("response mismatch");
                new SecurityIdentifier(response.owner.ownerSid); Wire.Utc(response.owner.acquiredAtUtc);
                if (Wire.Utc(response.owner.acquiredAtUtc) > begin || Wire.Utc(response.owner.processStartedAtUtc) > Wire.Utc(response.owner.acquiredAtUtc))
                    throw new IOException("acquisitionMismatch");
                if (budget.ElapsedMilliseconds > 500) throw new IOException("transportTimeout");
                // Only this client-side comparison sets affirmative binding statuses.
                result.state = "observed"; result.reason = null; result.currentOwnership = "observedActive";
                result.bindingStatus = "originalHandleObserved"; result.completeness = "boundOriginalHandle";
                result.senderBinding = "osPidAndStartConfirmed"; result.acquisitionBinding = "registeredOriginalStream";
                result.metadataBinding = "equalOriginalSha256"; result.objectBinding = "equalFileIdInfo";
                result.queryStartedAtUtc = response.queryStartedAtUtc; result.queryCompletedAtUtc = response.queryCompletedAtUtc;
                result.receivedAtUtc = received; result.owner = response.owner; result.requestId = request.requestId;
                result.lockId = response.lockId; result.attemptOrdinal = response.attemptOrdinal;
                result.originalMetadataHash = response.originalMetadataHash; result.objectIdentity = response.objectIdentity;
            } catch (Exception e) {
                string reason = e is TimeoutException ? "transportTimeout" : e is UnauthorizedAccessException ? "endpointUnavailable" : AllowedReason(e.Message);
                result = new Observation { reason = reason };
            }
            finally {
                bool cleanupConfirmed = true;
                if (pipe != null) cleanupConfirmed = pipe.CancelAndDispose() && pipe.IoTerminal;
                try { if (process != null) process.Dispose(); } catch { cleanupConfirmed = false; }
                if (cleanupConfirmed) result.diagnosticCompletedAtUtc = DateTime.UtcNow.ToString("o");
                else result = new Observation { reason = "clientCleanupUnconfirmed" };
            }
            return result;
        }
        static string AllowedReason(string reason) {
            switch (reason) {
                case "busy": case "stopping": case "queryFailed": case "objectMismatch": case "acquisitionMismatch":
                case "senderMismatch": case "transportTimeout": case "endpointUnavailable": return reason;
                case "metadataMismatch": case "response mismatch": case "invalid UTC": return "acquisitionMismatch";
                default: return "routeOrResponseUnavailable";
            }
        }
    }
}
