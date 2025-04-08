using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using NotesServer.Data;
using NotesServer.Models;
using NotesServer.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

namespace NotesServer.Controllers
{
    [Authorize]
    [Route("api/[controller]")]
    [ApiController]
    public class DatabaseController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly ICollaborationService _collaborationService;
        private readonly ILogger<DatabaseController> _logger;

        public DatabaseController(ApplicationDbContext context, ICollaborationService collaborationService, ILogger<DatabaseController> logger)
        {
            _context = context;
            _collaborationService = collaborationService;
            _logger = logger;
        }

        [HttpPost("{databaseId}/backup")]
        public async Task<IActionResult> CreateBackup(int databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var backupData = new BackupData
                {
                    DatabaseId = databaseId.ToString(),
                    UserId = userId,
                    Notes = await _context.Notes.Where(n => n.DatabaseId == databaseId).ToListAsync(),
                    Folders = await _context.Folders.Where(f => f.DatabaseId == databaseId).ToListAsync(),
                    ScheduleEntries = await _context.ScheduleEntries.Where(s => s.DatabaseId == databaseId).ToListAsync(),
                    PinboardNotes = await _context.PinboardNotes.Where(p => p.DatabaseId == databaseId).ToListAsync(),
                    Connections = await _context.Connections.Where(c => c.DatabaseId == databaseId).ToListAsync(),
                    NoteImages = await _context.NoteImages.Where(i => i.DatabaseId == databaseId).ToListAsync()
                };

                await _collaborationService.SaveDatabaseBackupAsync(databaseId, userId, backupData);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating backup for database {DatabaseId}", databaseId);
                return StatusCode(500, "Internal server error occurred while creating backup");
            }
        }

        [HttpGet("{databaseId}/backup")]
        public async Task<IActionResult> GetBackup(int databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var backupData = await _collaborationService.GetDatabaseBackupAsync(databaseId, userId);
                if (backupData == null)
                {
                    return NotFound("Backup not found");
                }

                return Ok(backupData);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving backup for database {DatabaseId}", databaseId);
                return StatusCode(500, "Internal server error occurred while retrieving backup");
            }
        }

        [HttpPost("{databaseId}/backup/restore")]
        public async Task<IActionResult> RestoreFromBackup(int databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var backupData = await _collaborationService.GetDatabaseBackupAsync(databaseId, userId);
                if (backupData == null)
                {
                    return NotFound("Backup not found");
                }

                // Удаляем существующие данные
                var existingNotes = _context.Notes.Where(n => n.DatabaseId == databaseId);
                var existingFolders = _context.Folders.Where(f => f.DatabaseId == databaseId);
                var existingScheduleEntries = _context.ScheduleEntries.Where(s => s.DatabaseId == databaseId);
                var existingPinboardNotes = _context.PinboardNotes.Where(p => p.DatabaseId == databaseId);
                var existingConnections = _context.Connections.Where(c => c.DatabaseId == databaseId);
                var existingNoteImages = _context.NoteImages.Where(i => i.DatabaseId == databaseId);

                _context.Notes.RemoveRange(existingNotes);
                _context.Folders.RemoveRange(existingFolders);
                _context.ScheduleEntries.RemoveRange(existingScheduleEntries);
                _context.PinboardNotes.RemoveRange(existingPinboardNotes);
                _context.Connections.RemoveRange(existingConnections);
                _context.NoteImages.RemoveRange(existingNoteImages);

                // Восстанавливаем данные из резервной копии
                await _context.Notes.AddRangeAsync(backupData.Notes);
                await _context.Folders.AddRangeAsync(backupData.Folders);
                await _context.ScheduleEntries.AddRangeAsync(backupData.ScheduleEntries);
                await _context.PinboardNotes.AddRangeAsync(backupData.PinboardNotes);
                await _context.Connections.AddRangeAsync(backupData.Connections);
                await _context.NoteImages.AddRangeAsync(backupData.NoteImages);

                await _context.SaveChangesAsync();
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error restoring backup for database {DatabaseId}", databaseId);
                return StatusCode(500, "Internal server error occurred while restoring backup");
            }
        }
    }
} 