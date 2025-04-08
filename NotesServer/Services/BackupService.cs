using System.Text.Json;
using NotesServer.Models;

namespace NotesServer.Services;

public interface IBackupService
{
    Task SaveBackupAsync(string userId, BackupData backupData);
    Task<BackupData?> GetBackupAsync(string userId);
}

public class BackupService : IBackupService
{
    private readonly string _backupDirectory;
    private readonly ILogger<BackupService> _logger;

    public BackupService(ILogger<BackupService> logger)
    {
        _logger = logger;
        _backupDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "backups");
        Directory.CreateDirectory(_backupDirectory);
        _logger.LogInformation("Backup directory created at: {BackupDirectory}", _backupDirectory);
    }

    public async Task SaveBackupAsync(string userId, BackupData backupData)
    {
        var backupPath = GetBackupPath(userId);
        _logger.LogInformation("Saving backup for user {UserId} to {BackupPath}", userId, backupPath);

        _logger.LogInformation("Saving backup data: {Folders} folders, {Notes} notes, {Schedule} schedule entries, {PinboardNotes} pinboard notes, {Connections} connections, {Images} images",
            backupData.Folders.Count,
            backupData.Notes.Count,
            backupData.ScheduleEntries.Count,
            backupData.PinboardNotes.Count,
            backupData.Connections.Count,
            backupData.NoteImages.Count);

        var json = JsonSerializer.Serialize(backupData, new JsonSerializerOptions
        {
            WriteIndented = true
        });

        await File.WriteAllTextAsync(backupPath, json);
        _logger.LogInformation("Backup saved successfully for user {UserId}", userId);
    }

    public async Task<BackupData?> GetBackupAsync(string userId)
    {
        var backupPath = GetBackupPath(userId);
        _logger.LogInformation("Attempting to load backup for user {UserId} from {BackupPath}", userId, backupPath);

        if (!File.Exists(backupPath))
        {
            _logger.LogWarning("No backup found for user {UserId}", userId);
            return null;
        }

        var json = await File.ReadAllTextAsync(backupPath);
        _logger.LogInformation("Loaded backup JSON: {Json}", json);

        var backup = JsonSerializer.Deserialize<BackupData>(json);
        
        if (backup != null)
        {
            _logger.LogInformation("Deserialized backup data: {Folders} folders, {Notes} notes, {Schedule} schedule entries, {PinboardNotes} pinboard notes, {Connections} connections, {Images} images",
                backup.Folders.Count,
                backup.Notes.Count,
                backup.ScheduleEntries.Count,
                backup.PinboardNotes.Count,
                backup.Connections.Count,
                backup.NoteImages.Count);
        }
        else
        {
            _logger.LogWarning("Failed to deserialize backup data for user {UserId}", userId);
        }

        _logger.LogInformation("Backup loaded successfully for user {UserId}", userId);
        return backup;
    }

    private string GetBackupPath(string userId)
    {
        return Path.Combine(_backupDirectory, $"{userId}.json");
    }
} 