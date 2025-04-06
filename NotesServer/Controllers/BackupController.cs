using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using NotesServer.Models;
using NotesServer.Services;
using System.Security.Claims;

namespace NotesServer.Controllers;

[ApiController]
[Route("api/[controller]")]
public class BackupController : ControllerBase
{
    private readonly IBackupService _backupService;
    private readonly ILogger<BackupController> _logger;

    public BackupController(IBackupService backupService, ILogger<BackupController> logger)
    {
        _backupService = backupService;
        _logger = logger;
    }

    [Authorize]
    [HttpPost("upload")]
    public async Task<IActionResult> UploadBackup([FromBody] BackupData? backupData)
    {
        try
        {
            _logger.LogInformation("Received backup upload request");
            _logger.LogInformation("Authorization header: {AuthHeader}", Request.Headers["Authorization"].ToString());
            
            if (backupData == null)
            {
                _logger.LogWarning("Backup data is null");
                return BadRequest(new { message = "Backup data is required" });
            }
            
            // Log all claims in the token
            foreach (var claim in User.Claims)
            {
                _logger.LogInformation("Claim: {Type} = {Value}", claim.Type, claim.Value);
            }
            
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                _logger.LogWarning("User ID not found in token");
                return Unauthorized();
            }

            _logger.LogInformation("User ID from token: {UserId}", userId);
            _logger.LogInformation("Received backup data for user {UserId}: {Folders} folders, {Notes} notes, {Schedule} schedule entries, {PinboardNotes} pinboard notes, {Connections} connections, {Images} images",
                userId, 
                backupData.Folders.Count, 
                backupData.Notes.Count, 
                backupData.Schedule.Count,
                backupData.PinboardNotes.Count,
                backupData.Connections.Count,
                backupData.Images.Count);

            await _backupService.SaveBackupAsync(userId, backupData);
            return Ok(new { message = "Backup saved successfully" });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error saving backup");
            return StatusCode(500, new { message = "Error saving backup", error = ex.Message });
        }
    }

    [Authorize]
    [HttpGet("download")]
    public async Task<IActionResult> DownloadBackup()
    {
        try
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
            {
                return Unauthorized();
            }

            var backup = await _backupService.GetBackupAsync(userId);
            if (backup == null)
            {
                return NotFound(new { message = "No backup found" });
            }

            _logger.LogInformation("Sending backup data for user {UserId}: {Folders} folders, {Notes} notes, {Images} images",
                userId, backup.Folders.Count, backup.Notes.Count, backup.Images.Count);

            return Ok(backup);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error downloading backup");
            return StatusCode(500, new { message = "Error downloading backup", error = ex.Message });
        }
    }
} 