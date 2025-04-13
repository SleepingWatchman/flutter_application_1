using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
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
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class CollaborationController : ControllerBase
    {
        private readonly ICollaborationService _collaborationService;
        private readonly ILogger<CollaborationController> _logger;

        public CollaborationController(ICollaborationService collaborationService, ILogger<CollaborationController> logger)
        {
            _collaborationService = collaborationService;
            _logger = logger;
        }

        [HttpGet("databases")]
        public async Task<IActionResult> GetDatabases()
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var databases = await _collaborationService.GetUserDatabasesAsync(userId);
                return Ok(databases);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении списка баз данных");
                return StatusCode(500, "Ошибка при получении списка баз данных");
            }
        }

        [HttpPost("databases")]
        public async Task<IActionResult> CreateDatabase()
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                var database = await _collaborationService.CreateDatabaseAsync(userId);
                return Ok(database);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при создании базы данных");
                return StatusCode(500, "Ошибка при создании базы данных");
            }
        }

        [HttpDelete("databases/{id}")]
        public async Task<IActionResult> DeleteDatabase(int id)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                await _collaborationService.DeleteDatabaseAsync(id, userId);
                return Ok();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Ошибка при удалении базы данных {id}");
                return StatusCode(500, "Ошибка при удалении базы данных");
            }
        }

        [HttpPost("databases/{databaseId}/backup")]
        public async Task<IActionResult> UploadDatabaseBackup(int databaseId, [FromBody] BackupData backupData)
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
                    return NotFound("База данных не найдена");
                }

                await _collaborationService.SaveDatabaseBackupAsync(databaseId, userId, backupData);
                return Ok(new { message = "Резервная копия успешно сохранена" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при сохранении резервной копии базы данных");
                return StatusCode(500, "Ошибка при сохранении резервной копии базы данных");
            }
        }

        [HttpGet("databases/{databaseId}/backup")]
        public async Task<IActionResult> DownloadDatabaseBackup(int databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                try
                {
                    var backup = await _collaborationService.GetDatabaseBackupAsync(databaseId, userId);
                    return Ok(backup);
                }
                catch (Exception ex) when (ex.Message == "Резервная копия не найдена" || ex.Message == "База данных не найдена")
                {
                    return NotFound(ex.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении резервной копии базы данных");
                return StatusCode(500, "Ошибка при получении резервной копии базы данных");
            }
        }

        [HttpGet("databases/{databaseId}")]
        public async Task<IActionResult> GetDatabase(int databaseId)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                try
                {
                    var database = await _collaborationService.GetDatabaseAsync(databaseId, userId);
                    return Ok(database);
                }
                catch (Exception ex) when (ex.Message == "База данных не найдена")
                {
                    return NotFound(ex.Message);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при получении информации о базе данных");
                return StatusCode(500, "Ошибка при получении информации о базе данных");
            }
        }

        [HttpPost("databases/{databaseId}/replace")]
        public async Task<IActionResult> ReplaceLocalDatabase(int databaseId, [FromBody] BackupData backupData)
        {
            try
            {
                var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
                if (string.IsNullOrEmpty(userId))
                {
                    return Unauthorized();
                }

                await _collaborationService.ReplaceLocalDatabaseAsync(databaseId, userId, backupData);
                return Ok(new { message = "Данные в локальной базе успешно заменены" });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ошибка при замене данных в локальной базе");
                return StatusCode(500, "Ошибка при замене данных в локальной базе");
            }
        }
    }
} 