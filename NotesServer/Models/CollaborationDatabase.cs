using System;
using System.ComponentModel.DataAnnotations;
using SQLite;

namespace NotesServer.Models
{
    public class CollaborationDatabase
    {
        [Key]
        public string Id { get; set; } = string.Empty;
        [Required]
        public string UserId { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
        [Required]
        public string DatabaseName { get; set; } = string.Empty;
        [Required]
        public string ConnectionString { get; set; } = string.Empty;
    }
} 