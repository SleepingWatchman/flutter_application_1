using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using NotesServer.Models;
using NotesServer.Services;
using System.Security.Claims;
using Microsoft.Extensions.Configuration;

namespace NotesServer.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class UserBackupController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private const string USER_BACKUPS_DIR = "user_backups";

    public UserBackupController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("upload")]
    public async Task<IActionResult> UploadBackup([FromForm] IFormFile file)
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var userBackupDir = Path.Combine(USER_BACKUPS_DIR, userId);
            Directory.CreateDirectory(userBackupDir);

            var backupPath = Path.Combine(userBackupDir, $"backup_{DateTime.Now:yyyyMMdd_HHmmss}.json");
            using (var stream = new FileStream(backupPath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            return Ok(new { message = "Резервная копия успешно загружена" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = $"Ошибка при загрузке резервной копии: {ex.Message}" });
        }
    }

    [HttpGet("download/latest")]
    public async Task<IActionResult> DownloadLatestBackup()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var userBackupDir = Path.Combine(USER_BACKUPS_DIR, userId);
            if (!Directory.Exists(userBackupDir))
            {
                return NotFound(new { message = "Резервные копии не найдены" });
            }

            var latestBackup = Directory
                .GetFiles(userBackupDir, "backup_*.json")
                .OrderByDescending(f => f)
                .FirstOrDefault();

            if (latestBackup == null)
            {
                return NotFound(new { message = "Резервные копии не найдены" });
            }

            var memory = new MemoryStream();
            using (var stream = new FileStream(latestBackup, FileMode.Open))
            {
                await stream.CopyToAsync(memory);
            }
            memory.Position = 0;

            return File(memory, "application/json", Path.GetFileName(latestBackup));
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = $"Ошибка при загрузке резервной копии: {ex.Message}" });
        }
    }
}

[ApiController]
[Route("api/[controller]")]
public class CollaborationBackupController : ControllerBase
{
    private readonly IConfiguration _configuration;
    private const string COLLAB_BACKUPS_DIR = "collaboration_backups";

    public CollaborationBackupController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    [HttpPost("{databaseId}/upload")]
    public async Task<IActionResult> UploadCollaborationBackup(string databaseId, [FromForm] IFormFile file)
    {
        try
        {
            var collabBackupDir = Path.Combine(COLLAB_BACKUPS_DIR, databaseId);
            Directory.CreateDirectory(collabBackupDir);

            var backupPath = Path.Combine(collabBackupDir, $"backup_{DateTime.Now:yyyyMMdd_HHmmss}.json");
            using (var stream = new FileStream(backupPath, FileMode.Create))
            {
                await file.CopyToAsync(stream);
            }

            return Ok(new { message = "Резервная копия совместной базы данных успешно загружена" });
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = $"Ошибка при загрузке резервной копии: {ex.Message}" });
        }
    }

    [HttpGet("{databaseId}/download/latest")]
    public async Task<IActionResult> DownloadLatestCollaborationBackup(string databaseId)
    {
        try
        {
            var collabBackupDir = Path.Combine(COLLAB_BACKUPS_DIR, databaseId);
            if (!Directory.Exists(collabBackupDir))
            {
                return NotFound(new { message = "Резервные копии не найдены" });
            }

            var latestBackup = Directory
                .GetFiles(collabBackupDir, "backup_*.json")
                .OrderByDescending(f => f)
                .FirstOrDefault();

            if (latestBackup == null)
            {
                return NotFound(new { message = "Резервные копии не найдены" });
            }

            var memory = new MemoryStream();
            using (var stream = new FileStream(latestBackup, FileMode.Open))
            {
                await stream.CopyToAsync(memory);
            }
            memory.Position = 0;

            return File(memory, "application/json", Path.GetFileName(latestBackup));
        }
        catch (Exception ex)
        {
            return BadRequest(new { message = $"Ошибка при загрузке резервной копии: {ex.Message}" });
        }
    }
} 