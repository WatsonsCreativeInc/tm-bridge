' run_runner_hidden.vbs (2026-10-29 v3) — launch the @typingmind/mcp runner
' with NO console window and NO cmd.exe in the chain.
' v3: direct node invocation, cache path resolved at runtime (newest
' @typingmind/mcp entry wins). Falls back to npx only if no cached
' entry exists. Note: VBScript Or does not short-circuit — the
' ElseIf structure below is deliberate.
Option Explicit
Dim fso, sh, tok, tokenFile, cacheDir, best, bestDate, hashDir, cand, f
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("Wscript.Shell")

tokenFile = "C:\Users\shawn\.tm-bridge\runner_token.txt"
If Not fso.FileExists(tokenFile) Then WScript.Quit 1
tok = Trim(fso.OpenTextFile(tokenFile, 1).ReadAll())
If tok = "" Then WScript.Quit 1

cacheDir = "C:\Users\shawn\AppData\Local\npm-cache\_npx"
best = ""
bestDate = ""

If fso.FolderExists(cacheDir) Then
  For Each hashDir In fso.GetFolder(cacheDir).SubFolders
    cand = hashDir.Path & "\node_modules\@typingmind\mcp\bin\index.js"
    If fso.FileExists(cand) Then
      Set f = fso.GetFile(cand)
      If best = "" Then
        best = cand
        bestDate = f.DateLastModified
      ElseIf f.DateLastModified > bestDate Then
        best = cand
        bestDate = f.DateLastModified
      End If
    End If
  Next
End If

sh.Environment("PROCESS")("PORT") = "50880"

If best <> "" Then
  sh.Run """C:\Program Files\nodejs\node.exe"" """ & best & """ " & tok, 0, False
Else
  sh.Run "cmd.exe /c npx -y @typingmind/mcp " & tok, 0, False
End If
