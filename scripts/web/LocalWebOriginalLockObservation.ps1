# Private observer; declarations are compiled only on a future explicit observation.
# This proposal must not be imported or invoked during content review.
function Get-LocalWebOriginalLockObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StorePath)
    $started = [DateTime]::UtcNow
    $result = [ordered]@{
        state='unknown'; owner=$null; currentOwnership='unconfirmed'
        bindingStatus='untrustedProducer'; reason='trusted unique producer binding unavailable'
        sourceReference='originalLockRead/v1'; originalMetadataHash=$null
        originalIdentity=$null; originalByteCount=$null; writerEvidence=$null
        observedAt=$null; readWindow=$null; completeness='unknown'; handleClosing=@()
    }
    $closing = $null
    try {
        $path = [IO.Path]::GetFullPath($StorePath) + '.lock'
        # Reject every visible reparse ancestor; races still prohibit owner attribution.
        $candidate = $path
        while ($candidate) {
            if (([IO.File]::GetAttributes($candidate) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'unsafe path' }
            $candidate = [IO.Path]::GetDirectoryName($candidate)
        }
        if (-not ('AgentOrg.PrivateOriginalLockReadV1' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Collections.Generic;
namespace AgentOrg {
 public static class PrivateOriginalLockReadV1 {
  const uint ReadAccess=0x80000000, FullShare=7, NoWriteShare=5;
  [StructLayout(LayoutKind.Sequential)] struct FileIdInfo {
   public ulong Volume;
   [MarshalAs(UnmanagedType.ByValArray, SizeConst=16)] public byte[] Id;
  }
  [StructLayout(LayoutKind.Sequential)] struct FileStandardInfo {
   public long AllocationSize, EndOfFile;
   public uint NumberOfLinks;
   [MarshalAs(UnmanagedType.U1)] public bool DeletePending;
   [MarshalAs(UnmanagedType.U1)] public bool Directory;
  }
  // One owner per private CreateFile result; no borrowed/raw handle escapes.
  sealed class PrivateHandle : SafeHandle {
   internal bool CloseAttempted, CloseSucceeded, CloseException;
   internal int? CloseWin32Error;
   public PrivateHandle() : base(new IntPtr(-1),true) {}
   public override bool IsInvalid { get { return handle==IntPtr.Zero || handle==new IntPtr(-1); } }
   protected override bool ReleaseHandle() {
    CloseAttempted=true;
    try {
     CloseSucceeded=CloseHandle(handle);
     CloseWin32Error=CloseSucceeded ? 0 : Marshal.GetLastWin32Error();
    } catch { CloseSucceeded=false; CloseException=true; CloseWin32Error=null; }
    // One terminal release attempt even on false; never retry a possibly reused value.
    return CloseSucceeded;
   }
  }
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", EntryPoint="CreateFileW", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern PrivateHandle Open(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll", EntryPoint="GetFileInformationByHandleEx", SetLastError=true)]
  static extern bool GetId(PrivateHandle handle,int kind,out FileIdInfo info,uint size);
  [DllImport("kernel32.dll", EntryPoint="GetFileInformationByHandleEx", SetLastError=true)]
  static extern bool GetStandard(PrivateHandle handle,int kind,out FileStandardInfo info,uint size);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool SetFilePointerEx(PrivateHandle handle,long distance,out long position,uint method);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool ReadFile(PrivateHandle handle,[Out] byte[] buffer,uint count,out uint read,IntPtr overlapped);
  public sealed class CloseStatus {
   public string PathRole;
   public bool ValidHandle, CloseAttempted, CloseSucceeded, CloseException;
   public int? CloseWin32Error;
  }
  public sealed class Observation {
   public string Identity, MetadataHash, BeforeProbeAtUtc, AfterProbeAtUtc;
   public int ByteCount, BeforeError, AfterError;
  }
  static void ClosePrivate(PrivateHandle handle,string role,List<CloseStatus> closing) {
   if(handle==null) return; // Open threw before returning a handle.
   bool valid=!handle.IsInvalid;
   // Do not throw during cleanup: the outer original-owner finally must still run.
   bool disposeException=false;
   try { handle.Dispose(); } catch { disposeException=true; }
   closing.Add(new CloseStatus { PathRole=role, ValidHandle=valid,
    CloseAttempted=handle.CloseAttempted, CloseSucceeded=handle.CloseSucceeded,
    CloseWin32Error=handle.CloseWin32Error, CloseException=handle.CloseException || disposeException });
  }
  static void RequireClosed(List<CloseStatus> closing) {
   foreach(CloseStatus status in closing) {
    if(status.CloseException || (status.ValidHandle && (!status.CloseAttempted || !status.CloseSucceeded)))
     throw new IOException("private handle closing unconfirmed");
   }
  }
  static PrivateHandle OpenRead(string path,uint share,string role,List<CloseStatus> closing) {
   // OPEN_EXISTING; no security attributes, inheritance, DELETE or DeleteOnClose.
   PrivateHandle handle=null;
   bool transferred=false;
   try {
    handle=Open(path,ReadAccess,share,IntPtr.Zero,3,0x80,IntPtr.Zero);
    int error=Marshal.GetLastWin32Error();
    if(handle.IsInvalid) throw new Win32Exception(error);
    transferred=true;
    return handle; // Ownership transfers only to the caller's immediate finally.
   } finally {
    if(!transferred) ClosePrivate(handle,role,closing);
   }
  }
  static string Identity(PrivateHandle handle) {
   FileIdInfo id;
   if(!GetId(handle,18,out id,(uint)Marshal.SizeOf(typeof(FileIdInfo)))) throw new Win32Exception(Marshal.GetLastWin32Error());
   FileStandardInfo standard;
   if(!GetStandard(handle,1,out standard,(uint)Marshal.SizeOf(typeof(FileStandardInfo)))) throw new Win32Exception(Marshal.GetLastWin32Error());
   if(standard.Directory || standard.DeletePending || standard.NumberOfLinks!=1) throw new IOException("ambiguous or delete-pending original");
   return id.Volume.ToString("x16")+":"+BitConverter.ToString(id.Id).Replace("-", "").ToLowerInvariant();
  }
  static void ConfirmPath(string path,string identity,string role,List<CloseStatus> closing) {
   PrivateHandle handle=null;
   try {
    handle=OpenRead(path,FullShare,role,closing);
    if(Identity(handle)!=identity) throw new IOException("original path identity changed");
   } finally { ClosePrivate(handle,role,closing); }
   RequireClosed(closing);
  }
  static int Probe(string path,string role,List<CloseStatus> closing,out string at) {
   // DesiredAccess READ triggers the sharing algorithm; access0 cannot prove a writer.
   PrivateHandle probe=null;
   int error;
   at=null;
   try {
    probe=Open(path,ReadAccess,NoWriteShare,IntPtr.Zero,3,0x80,IntPtr.Zero);
    int openError=Marshal.GetLastWin32Error();
    at=DateTime.UtcNow.ToString("o"); // Open return, NOT a measured kernel instant.
    error=probe.IsInvalid ? openError : 0;
   } finally { ClosePrivate(probe,role,closing); }
   RequireClosed(closing);
   return error;
  }
  static byte[] ReadBounded(PrivateHandle handle) {
   long position;
   if(!SetFilePointerEx(handle,0,out position,0)) throw new Win32Exception(Marshal.GetLastWin32Error());
   if(position!=0) throw new IOException("original seek unconfirmed");
   using(MemoryStream bytes=new MemoryStream()) {
    byte[] buffer=new byte[4096];
    while(true) {
     uint requested=(uint)Math.Min(buffer.Length,65537-(int)bytes.Length);
     uint count;
     // Synchronous handle/buffer: no OVERLAPPED flag, no pending asynchronous I/O.
     if(!ReadFile(handle,buffer,requested,out count,IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
     if(count>requested) throw new IOException("original read count invalid");
     if(count==0) break;
     bytes.Write(buffer,0,(int)count);
     if(bytes.Length>65536) throw new IOException("original metadata exceeds byte limit");
    }
    if(bytes.Length==0) throw new IOException("empty original metadata");
    return bytes.ToArray();
   }
  }
  public static Observation Observe(string path,List<CloseStatus> closing) {
   string identity, beforeAt, afterAt;
   int before, after;
   byte[] first;
   PrivateHandle handle=null;
   try {
    handle=OpenRead(path,FullShare,"original",closing);
    identity=Identity(handle);
    ConfirmPath(path,identity,"controlBefore",closing);
    before=Probe(path,"probeBefore",closing,out beforeAt);
    if(before!=0 && before!=32) throw new Win32Exception(before);
    first=ReadBounded(handle);
    byte[] second=ReadBounded(handle);
    if(first.Length!=second.Length) throw new IOException("original byte read race");
    for(int i=0;i<first.Length;i++) if(first[i]!=second[i]) throw new IOException("original byte read race");
    if(Identity(handle)!=identity) throw new IOException("original identity changed");
    after=Probe(path,"probeAfter",closing,out afterAt);
    if(after!=0 && after!=32) throw new Win32Exception(after);
    ConfirmPath(path,identity,"controlAfter",closing);
   } finally { ClosePrivate(handle,"original",closing); }
   RequireClosed(closing); // Every returned private handle, before hashing/transport.
   using(SHA256 sha=SHA256.Create()) {
    return new Observation { Identity=identity, MetadataHash=BitConverter.ToString(sha.ComputeHash(first)).Replace("-", "").ToLowerInvariant(),
     ByteCount=first.Length, BeforeError=before, AfterError=after, BeforeProbeAtUtc=beforeAt, AfterProbeAtUtc=afterAt };
   }
  }
 }
}
"@ -ErrorAction Stop
        }
        $closing = New-Object 'System.Collections.Generic.List[AgentOrg.PrivateOriginalLockReadV1+CloseStatus]'
        $observation = [AgentOrg.PrivateOriginalLockReadV1]::Observe($path, $closing)
        $result.originalMetadataHash = $observation.MetadataHash
        $result.originalIdentity = [pscustomobject]@{ format='FILE_ID_INFO'; volumeAndFileId=$observation.Identity }
        $result.originalByteCount = $observation.ByteCount
        $both = $observation.BeforeError -eq 32 -and $observation.AfterError -eq 32
        $result.writerEvidence = [pscustomobject][ordered]@{
            qualification=$(if ($both) { 'readCompatibleSharingViolations' } else { 'notEstablished' })
            before=[pscustomobject]@{ atUtc=$observation.BeforeProbeAtUtc; win32Error=$observation.BeforeError }
            after=[pscustomobject]@{ atUtc=$observation.AfterProbeAtUtc; win32Error=$observation.AfterError }
            access='Read'; share='Read|Delete'; pathIdentity='equalAtSuccessfulBracketOpens'
            failedProbeIdentity='unavailable'; continuity='unconfirmedBetweenOpens'
            attribution='unknown'; validity='probeInstantsOnly'
        }
        $result.completeness='boundedBytesAndIdentity'
        # Self-declared JSON, SID/PID/host, a source hash and writable lifecycle files
        # are not a trusted producer attestation. Do not manufacture a positive owner.
    } catch {
        $result.reason='original read unavailable, unsafe, changed or native query/closing failed; ownership unknown'
        $result.completeness='unknown'
        $result.originalMetadataHash=$null; $result.originalIdentity=$null
        $result.originalByteCount=$null; $result.writerEvidence=$null
    } finally {
        if ($null -ne $closing) { $result.handleClosing=@($closing.ToArray()) }
        $finished = [DateTime]::UtcNow
        $result.observedAt=$finished.ToString('o')
        $result.readWindow=[pscustomobject]@{ startedAtUtc=$started.ToString('o'); completedAtUtc=$finished.ToString('o') }
    }
    return [pscustomobject]$result
}

# Additive source: this never promotes the conservative failed sharing probe.
function Get-LocalWebDirectOriginalLockObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StorePath)
    try {
        if (-not ('AgentOrg.LockDiagnosticsV1.Client' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot '../workitems/WorkItemStoreLockDiagnostics.cs') -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Runtime.Serialization.dll', 'System.Xml.dll') -ErrorAction Stop
        }
        return [AgentOrg.LockDiagnosticsV1.Client]::Observe($StorePath)
    } catch {
        return [pscustomobject][ordered]@{
            state='unknown'; owner=$null; currentOwnership='unconfirmed'; bindingStatus='unconfirmed'
            sourceReference='producerOriginalHandle/v1'; completeness='unknown'; reason='helperUnavailable'
            senderBinding=$null; acquisitionBinding=$null; metadataBinding=$null; objectBinding=$null
            queryStartedAtUtc=$null; queryCompletedAtUtc=$null; receivedAtUtc=$null
            diagnosticCompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        }
    }
}