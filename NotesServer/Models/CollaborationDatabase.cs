using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace NotesServer.Models
{
    public class CollaborationDatabase
    {
        [Key]
        public string Id { get; set; } = Guid.NewGuid().ToString();
        
        [Required]
        public string UserId { get; set; } = string.Empty;
        
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
        
        [Required]
        public string DatabaseName { get; set; } = string.Empty;
        
        [Required]
        public string ConnectionString { get; set; } = string.Empty;
    }
} 