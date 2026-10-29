// vault-test.js (2026-10-29) - diagnostic: replicate tm-bridge's readVaultSecret
// exactly for one secret and print what happens (result or the actual error).
const name = process.argv[2] || "tmKey";
const ps = [
  "$ErrorActionPreference='Stop'",
  "$s=@\"",
  "using System;using System.Runtime.InteropServices;public static class CM{",
  "[StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]public struct C{public int Flags;public int Type;public string TargetName;public string Comment;public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;public int CredentialBlobSize;public IntPtr CredentialBlob;public int Persist;public int AttributeCount;public IntPtr Attributes;public string TargetAlias;public string UserName;}",
  "[DllImport(\"advapi32.dll\",CharSet=CharSet.Unicode,EntryPoint=\"CredReadW\")]public static extern bool R(string t,int ty,int f,out IntPtr p);",
  "[DllImport(\"advapi32.dll\", EntryPoint=\"CredFree\")]public static extern void F(IntPtr c);}",
  "\"@",
  "Add-Type -TypeDefinition $s",
  "$p=[IntPtr]::Zero",
  "if(-not [CM]::R('TMB:" + name + "',1,0,[ref]$p)){exit 1}",
  "try{",
  "$c=[Runtime.InteropServices.Marshal]::PtrToStructure($p,[type][CM+C])",
  "$b=New-Object byte[] $c.CredentialBlobSize",
  "[Runtime.InteropServices.Marshal]::Copy($c.CredentialBlob,$b,0,$c.CredentialBlobSize)",
  "[Console]::Out.Write([Text.Encoding]::Unicode.GetString($b))",
  "}finally{[CM]::F($p)}"
].join("\r\n");
const encoded = Buffer.from(ps, "utf16le").toString("base64");
const { execSync } = require("child_process");
try {
  const out = execSync("powershell.exe -NoProfile -EncodedCommand " + encoded,
    { encoding: "utf8", windowsHide: true, timeout: 20000 });
  console.log("SUCCESS length=" + out.length + " value=" + JSON.stringify(out));
} catch (e) {
  console.log("FAILED");
  console.log("message: " + (e.message || "").split("\n")[0]);
  console.log("stderr: " + String(e.stderr || ""));
  console.log("status: " + e.status);
}
