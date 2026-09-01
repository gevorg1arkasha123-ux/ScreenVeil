using System;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;

internal static class ScreenVeilLauncher
{
    [STAThread]
    private static int Main(string[] args)
    {
        string baseDirectory = AppDomain.CurrentDomain.BaseDirectory;
        bool warningMode = args.Length > 0 && args[0] == "--warning";
        int warningSeconds = 30;
        if (warningMode && args.Length > 1) int.TryParse(args[1], out warningSeconds);
        string scriptPath = Path.Combine(baseDirectory, warningMode ? "warning.ps1" : "lock.ps1");
        string logDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ScreenVeil");
        string logPath = Path.Combine(logDirectory, "launcher.log");
        bool diagnosticsOnly = Environment.GetEnvironmentVariable("SCREENVEIL_DIAGNOSTIC") == "1";

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show("Не найден lock.ps1 рядом с ScreenVeil.exe.", "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        try
        {
            Environment.CurrentDirectory = baseDirectory;
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            using (PowerShell shell = PowerShell.Create())
            {
                runspace.ApartmentState = System.Threading.ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.ReuseThread;
                runspace.Open();
                shell.Runspace = runspace;
                shell.AddCommand(scriptPath);
                if (diagnosticsOnly && !warningMode) shell.AddParameter("DiagnosticsOnly");
                if (warningMode) shell.AddParameter("Seconds", warningSeconds);
                var results = shell.Invoke();
                if (shell.HadErrors)
                {
                    string message = string.Join(Environment.NewLine,
                        shell.Streams.Error.Select(error => error.ToString()).Take(4));
                    Directory.CreateDirectory(logDirectory);
                    File.AppendAllText(logPath, DateTime.Now.ToString("u") + " " + message + Environment.NewLine);
                    MessageBox.Show("Не удалось запустить блокировку:\n\n" + message,
                        "ScreenVeil", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return 1;
                }
                if (warningMode && results.Any(result =>
                    string.Equals(Convert.ToString(result.BaseObject), "CANCELLED", StringComparison.Ordinal)))
                    return 2;
            }
            return 0;
        }
        catch (Exception exception)
        {
            Directory.CreateDirectory(logDirectory);
            File.AppendAllText(logPath, DateTime.Now.ToString("u") + " " + exception + Environment.NewLine);
            MessageBox.Show("Ошибка ScreenVeil:\n\n" + exception.Message, "ScreenVeil",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}


