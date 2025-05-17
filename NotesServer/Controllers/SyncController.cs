using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NotesServer.Models;
using NotesServer.Data;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;
using System.IO;
using SQLite;
using System.Text.Json;

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SyncController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly ILogger<SyncController> _logger;
        private readonly SQLiteConnection _db;

        public SyncController(ApplicationDbContext context, ILogger<SyncController> logger, SQLiteConnection db)
        {
            _context = context;
            _logger = logger;
            _db = db;
        }

        [HttpPost("{databaseId}")]
        public async Task<ActionResult> SyncDatabase(string databaseId, [FromBody] SyncData data)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == databaseId && 
                    (db.OwnerId == userId || db.Collaborators.Contains(userId)));

            if (database == null) return NotFound();

            try
            {
                // Синхронизация заметок
                foreach (var note in data.Notes)
                {
                    var existingNote = _db.Find<Note>(note.Id);
                    if (existingNote != null)
                    {
                        _db.Update(note);
                    }
                    else
                    {
                        _db.Insert(note);
                    }
                }

                // Синхронизация папок
                foreach (var folder in data.Folders)
                {
                    var existingFolder = _db.Find<Folder>(folder.Id);
                    if (existingFolder != null)
                    {
                        _db.Update(folder);
                    }
                    else
                    {
                        _db.Insert(folder);
                    }
                }

                // Синхронизация записей расписания
                foreach (var entry in data.ScheduleEntries)
                {
                    var existingEntry = _db.Find<ScheduleEntry>(entry.Id);
                    if (existingEntry != null)
                    {
                        _db.Update(entry);
                    }
                    else
                    {
                        _db.Insert(entry);
                    }
                }

                // Синхронизация заметок на доске
                foreach (var note in data.PinboardNotes)
                {
                    var existingNote = _db.Find<PinboardNote>(note.Id);
                    if (existingNote != null)
                    {
                        _db.Update(note);
                    }
                    else
                    {
                        _db.Insert(note);
                    }
                }

                // Синхронизация связей
                foreach (var connection in data.Connections)
                {
                    var existingConnection = _db.Find<Connection>(connection.Id);
                    if (existingConnection != null)
                    {
                        _db.Update(connection);
                    }
                    else
                    {
                        _db.Insert(connection);
                    }
                }

                // Синхронизация изображений заметок
                foreach (var image in data.NoteImages)
                {
                    var existingImage = _db.Find<NoteImage>(image.Id);
                    if (existingImage != null)
                    {
                        _db.Update(image);
                    }
                    else
                    {
                        _db.Insert(image);
                    }
                }

                return Ok(new { message = "Синхронизация успешно завершена" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при синхронизации базы данных {databaseId}");
                return StatusCode(500, new { error = $"Ошибка синхронизации: {ex.Message}" });
            }
        }
    }

    public class SyncData
    {
        public List<Note> Notes { get; set; } = new();
        public List<Folder> Folders { get; set; } = new();
        public List<ScheduleEntry> ScheduleEntries { get; set; } = new();
        public List<PinboardNote> PinboardNotes { get; set; } = new();
        public List<Connection> Connections { get; set; } = new();
        public List<NoteImage> NoteImages { get; set; } = new();
    }
} 