using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Text.Json;

namespace NotesServer.Models
{
    public class SharedDatabase
    {
        [Key]
        public required string Id { get; set; }
        
        [Required]
        public required string Name { get; set; }
        
        [Required]
        public required string OwnerId { get; set; }
        
        [Required]
        public DateTime CreatedAt { get; set; }
        
        private string _collaboratorsJson = "[]";
        
        [Required]
        public List<string> Collaborators 
        { 
            get => JsonSerializer.Deserialize<List<string>>(_collaboratorsJson) ?? new List<string>();
            set => _collaboratorsJson = JsonSerializer.Serialize(value);
        }
        
        public string CollaboratorsJson
        {
            get => _collaboratorsJson;
            set => _collaboratorsJson = value;
        }
    }
} 