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

namespace NotesServer.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    [Authorize]
    public class SharedDatabaseController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public SharedDatabaseController(ApplicationDbContext context)
        {
            _context = context;
        }

        [HttpGet]
        public async Task<ActionResult<IEnumerable<SharedDatabase>>> GetUserDatabases()
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var databases = await _context.SharedDatabases
                .Where(db => db.OwnerId == userId || db.Collaborators.Contains(userId))
                .ToListAsync();

            return Ok(databases);
        }

        [HttpPost]
        public async Task<ActionResult<SharedDatabase>> CreateDatabase([FromBody] CreateDatabaseRequest request)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null)
            {
                Console.WriteLine("Unauthorized: User ID not found in token");
                return Unauthorized();
            }

            Console.WriteLine($"Creating database for user {userId} with name {request.Name}");

            var database = new SharedDatabase
            {
                Id = GenerateDatabaseId(),
                Name = request.Name,
                OwnerId = userId,
                CreatedAt = DateTime.UtcNow,
                Collaborators = new List<string> { userId }
            };

            _context.SharedDatabases.Add(database);
            await _context.SaveChangesAsync();

            Console.WriteLine($"Database created successfully with ID {database.Id}");
            return CreatedAtAction(nameof(GetDatabase), new { id = database.Id }, database);
        }

        [HttpGet("{id}")]
        public async Task<ActionResult<SharedDatabase>> GetDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && 
                    (db.OwnerId == userId || db.Collaborators.Contains(userId)));

            if (database == null) return NotFound();

            return Ok(database);
        }

        [HttpPost("{id}/import")]
        public async Task<ActionResult> ImportDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id);

            if (database == null) return NotFound();

            if (!database.Collaborators.Contains(userId))
            {
                database.Collaborators.Add(userId);
                await _context.SaveChangesAsync();
            }

            return Ok();
        }

        [HttpDelete("{id}")]
        public async Task<ActionResult> DeleteDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && db.OwnerId == userId);

            if (database == null) return NotFound();

            _context.SharedDatabases.Remove(database);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpPost("{id}/leave")]
        public async Task<ActionResult> LeaveDatabase(string id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null) return Unauthorized();

            var database = await _context.SharedDatabases
                .FirstOrDefaultAsync(db => db.Id == id && 
                    db.Collaborators.Contains(userId) && 
                    db.OwnerId != userId);

            if (database == null) return NotFound();

            database.Collaborators.Remove(userId);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        private string GenerateDatabaseId()
        {
            const string chars = "0123456789";
            var random = new Random();
            return new string(Enumerable.Repeat(chars, 12)
                .Select(s => s[random.Next(s.Length)]).ToArray());
        }
    }

    public class CreateDatabaseRequest
    {
        public required string Name { get; set; }
    }
} 