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

        [HttpGet("{databaseId}")]
        public async Task<IActionResult> GetDatabase(string databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var database = await _collaborationService.GetDatabaseAsync(databaseId, userId);
                if (database == null)
                {
                    return NotFound();
                }

                return Ok(database);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при получении базы данных {databaseId}");
                return BadRequest($"Ошибка при получении базы данных: {ex.Message}");
            }
        }

        [HttpPost("{databaseId}/backup")]
        public async Task<IActionResult> SaveDatabaseBackup(string databaseId, [FromBody] BackupData backupData)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                await _collaborationService.SaveDatabaseBackupAsync(databaseId, userId, backupData);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при сохранении резервной копии базы данных {databaseId}");
                return BadRequest($"Ошибка при сохранении резервной копии: {ex.Message}");
            }
        }

        [HttpGet("{databaseId}/backup")]
        public async Task<IActionResult> GetDatabaseBackup(string databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var backup = await _collaborationService.GetDatabaseBackupAsync(databaseId, userId);
                return Ok(backup);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при получении резервной копии базы данных {databaseId}");
                return BadRequest($"Ошибка при получении резервной копии: {ex.Message}");
            }
        }

        [HttpPost("{databaseId}/backup/restore")]
        public async Task<IActionResult> RestoreFromBackup(string databaseId)
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
                var existingNotes = _context.Notes.Where(n => n.DatabaseId == int.Parse(databaseId));
                var existingFolders = _context.Folders.Where(f => f.DatabaseId == int.Parse(databaseId));
                var existingScheduleEntries = _context.ScheduleEntries.Where(s => s.DatabaseId == int.Parse(databaseId));
                var existingPinboardNotes = _context.PinboardNotes.Where(p => p.DatabaseId == int.Parse(databaseId));
                var existingConnections = _context.Connections.Where(c => c.DatabaseId == int.Parse(databaseId));
                var existingNoteImages = _context.NoteImages.Where(i => i.DatabaseId == int.Parse(databaseId));

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
                _logger.LogError(ex, $"Ошибка при восстановлении из резервной копии базы данных {databaseId}");
                return BadRequest($"Ошибка при восстановлении из резервной копии: {ex.Message}");
            }
        }
    }
} 