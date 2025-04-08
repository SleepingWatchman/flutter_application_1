using System;
using System.ComponentModel.DataAnnotations;

namespace NotesServer.Models
{
    public class CollaborationDatabase
    {
        public int Id { get; set; }
        [Required]
        public string UserId { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        [Required]
        public string DatabaseName { get; set; } = string.Empty;
        [Required]
        public string ConnectionString { get; set; } = string.Empty;
    }
} 